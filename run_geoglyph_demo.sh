#!/bin/bash
# ============================================================
# 地上絵デモ 一発起動（テキスト → Claude AI → 軌跡 → 間引き → nav2巡回）
#   構成: [fake_tf] + nav2+地図 + endpoint + geoglyph_generator + waypoint_sender
#   使い方:
#     bash run_geoglyph_demo.sh          # オフライン(TB3無し, 偽TFでnav2フル起動)
#     bash run_geoglyph_demo.sh --real   # 実機(偽TF無し。別途TB3で robot.launch を起動)
#   環境変数で調整可:
#     TARGET_POINTS(既定100 表示密度) / NUM_WAYPOINTS(既定40 nav2WP数) / INSET(既定0.15 地図余白)
#   例: NUM_WAYPOINTS=60 INSET=0.05 bash run_geoglyph_demo.sh
#   APIキーは ~/vr_demo_ws/api_key.env（未設定ならMOCKで動作）。 Ctrl+C で全停止。
# ============================================================
set -u
REAL=0
[ "${1:-}" = "--real" ] && REAL=1
TARGET_POINTS=${TARGET_POINTS:-100}
NUM_WAYPOINTS=${NUM_WAYPOINTS:-40}
INSET=${INSET:-0.15}

# ROSのsetup.bashは未定義変数(AMENT_TRACE_SETUP_FILES等)を参照するため set -u を一時解除
set +u
source /opt/ros/humble/setup.bash
source ~/vr_demo_ws/install/setup.bash
set -u
export TURTLEBOT3_MODEL=burger
export ROS_DOMAIN_ID=30   # TB3と合わせて固定
# APIキー（未編集プレースホルダは無視）
if [ -f ~/vr_demo_ws/api_key.env ]; then
  source ~/vr_demo_ws/api_key.env
  [ "${ANTHROPIC_API_KEY:-}" = "ここに貼る" ] && unset ANTHROPIC_API_KEY
fi
MAP=~/vr_demo_ws/src/nav2_bringup_custom/maps/map_sfc.yaml
LOG=/tmp/geoglyph_demo; mkdir -p $LOG
IP=$(ip -4 addr | grep -oP '(?<=inet\s)192\.168\.\d+\.\d+' | head -1)

PIDS=()
cleanup() {
  echo; echo "[停止] 全ノードを終了します..."
  kill "${PIDS[@]}" 2>/dev/null
  pkill -9 -f static_transform_publisher 2>/dev/null
  pkill -9 -f component_container_isolated 2>/dev/null
  pkill -9 -f geoglyph_generator 2>/dev/null
  pkill -9 -f waypoint_sender 2>/dev/null
  pkill -9 -f default_server_endpoint 2>/dev/null
  pkill -9 -x rviz2 2>/dev/null
  echo "[停止] 完了"; exit 0
}
trap cleanup INT TERM

# 既存インスタンス掃除
pkill -9 -f component_container_isolated 2>/dev/null
pkill -9 -f geoglyph_generator 2>/dev/null
pkill -9 -f waypoint_sender 2>/dev/null
pkill -9 -f static_transform_publisher 2>/dev/null
sleep 2

echo "=== 地上絵デモ起動 (mode: $([ $REAL -eq 1 ] && echo 実機 || echo オフライン)) ==="
echo "    密度=$TARGET_POINTS点 / WP=$NUM_WAYPOINTS / inset=$INSET / APIキー=$([ -n "${ANTHROPIC_API_KEY:-}" ] && echo Claude || echo MOCK)"

if [ $REAL -eq 0 ]; then
  echo "[1/5] 偽TF発行(TB3無し用)..."
  ros2 run tf2_ros static_transform_publisher 0 0 0 0 0 0 map odom >$LOG/tf1.log 2>&1 & PIDS+=($!)
  ros2 run tf2_ros static_transform_publisher 0 0 0 0 0 0 odom base_footprint >$LOG/tf2.log 2>&1 & PIDS+=($!)
  ros2 run tf2_ros static_transform_publisher 0 0 0 0 0 0 base_footprint base_link >$LOG/tf3.log 2>&1 & PIDS+=($!)
  ros2 run tf2_ros static_transform_publisher 0 0 0.1 0 0 0 base_link base_scan >$LOG/tf4.log 2>&1 & PIDS+=($!)
else
  echo "[1/5] 実機モード: 偽TFはスキップ（TB3側で robot.launch.py を起動しておくこと）"
fi

echo "[2/5] nav2 + 地図 起動..."
ros2 launch nav2_bringup bringup_launch.py use_sim_time:=False map:="$MAP" >$LOG/nav2.log 2>&1 & PIDS+=($!)

echo "[3/5] ROS-TCP-Endpoint 起動 (0.0.0.0:10000)..."
ros2 run ros_tcp_endpoint default_server_endpoint --ros-args -p ROS_IP:=0.0.0.0 >$LOG/endpoint.log 2>&1 & PIDS+=($!)

echo "    nav2起動待ち(28s)..."; sleep 28

echo "[4/5] 生成ノード(geoglyph_generator) 起動..."
ros2 run geoglyph geoglyph_generator --ros-args \
  -p target_points:=$TARGET_POINTS -p inset:=$INSET >$LOG/generator.log 2>&1 & PIDS+=($!)

echo "[5/5] 送出ノード(waypoint_sender, 実行トリガ待ち) 起動..."
ros2 run geoglyph waypoint_sender --ros-args \
  -p auto_execute:=false -p num_waypoints:=$NUM_WAYPOINTS >$LOG/sender.log 2>&1 & PIDS+=($!)
sleep 3

echo "[RViz] 2D Pose Estimate用に起動 (ソフトGL)..."
LIBGL_ALWAYS_SOFTWARE=1 DISPLAY=:0 QT_X11_NO_MITSHM=1 ros2 run rviz2 rviz2 -d /opt/ros/humble/share/nav2_bringup/rviz/nav2_default_view.rviz >$LOG/rviz.log 2>&1 & PIDS+=($!)

echo ""
echo "=== 起動完了 ==="
echo "  このPCのIP : ${IP:-不明}   (Unity ROS Settings: ROS IP=${IP}, Port=10000, ROS2)"
echo "  Unity操作  : R=お題送信(/draw_request) → 軌跡表示 / Space=実行(/execute_geoglyph) → 巡回"
echo "  手動テスト : ros2 topic pub --once /draw_request std_msgs/msg/String \"{data: 'うずまき'}\""
echo "               ros2 topic pub --once /execute_geoglyph std_msgs/msg/Bool \"{data: true}\""
echo "  ログ       : $LOG/*.log"
[ $REAL -eq 0 ] && echo "  ※オフライン: nav2フル起動・巡回計画は走るがTB3無しで実移動しない（配線確認まで）"
echo "  Ctrl+C で全停止"
echo ""
tail -f $LOG/generator.log $LOG/sender.log
