#!/bin/bash
# ============================================================
# ナビ単独デモ 一発起動（VRゴール送信 → nav2 → TB3移動）
#   構成: [fake_tf] + nav2+地図 + endpoint + nav2_unity_pipeline
#   使い方:
#     bash run_nav_demo.sh          # オフライン(TB3無し, 偽TFでnav2フル起動)
#     bash run_nav_demo.sh --real   # 実機(偽TF無し。別途TB3で robot.launch を起動しておくこと)
#   Ctrl+C で全ノード一括停止。
# ============================================================
set -u
REAL=0
[ "${1:-}" = "--real" ] && REAL=1

# ROSのsetup.bashは未定義変数(AMENT_TRACE_SETUP_FILES等)を参照するため set -u を一時解除
set +u
source /opt/ros/humble/setup.bash
source ~/vr_demo_ws/install/setup.bash
set -u
export TURTLEBOT3_MODEL=burger
export ROS_DOMAIN_ID=30   # TB3と合わせて固定
MAP=~/vr_demo_ws/src/nav2_bringup_custom/maps/map_sfc.yaml
LOG=/tmp/nav_demo; mkdir -p $LOG
IP=$(ip -4 addr | grep -oP '(?<=inet\s)192\.168\.\d+\.\d+' | head -1)

PIDS=()
cleanup() {
  echo; echo "[停止] 全ノードを終了します..."
  kill "${PIDS[@]}" 2>/dev/null
  pkill -9 -f static_transform_publisher 2>/dev/null
  pkill -9 -f component_container_isolated 2>/dev/null
  pkill -9 -f nav2_unity_pipeline 2>/dev/null
  pkill -9 -f default_server_endpoint 2>/dev/null
  pkill -9 -x rviz2 2>/dev/null
  echo "[停止] 完了"; exit 0
}
trap cleanup INT TERM

# 既存インスタンスを掃除（多重起動防止）
pkill -9 -f component_container_isolated 2>/dev/null
pkill -9 -f nav2_unity_pipeline 2>/dev/null
pkill -9 -f static_transform_publisher 2>/dev/null
sleep 2

echo "=== ナビ単独デモ起動 (mode: $([ $REAL -eq 1 ] && echo 実機 || echo オフライン)) ==="

if [ $REAL -eq 0 ]; then
  echo "[1/4] 偽TF発行(TB3無し用)..."
  ros2 run tf2_ros static_transform_publisher 0 0 0 0 0 0 map odom >$LOG/tf1.log 2>&1 & PIDS+=($!)
  ros2 run tf2_ros static_transform_publisher 0 0 0 0 0 0 odom base_footprint >$LOG/tf2.log 2>&1 & PIDS+=($!)
  ros2 run tf2_ros static_transform_publisher 0 0 0 0 0 0 base_footprint base_link >$LOG/tf3.log 2>&1 & PIDS+=($!)
  ros2 run tf2_ros static_transform_publisher 0 0 0.1 0 0 0 base_link base_scan >$LOG/tf4.log 2>&1 & PIDS+=($!)
else
  echo "[1/4] 実機モード: 偽TFはスキップ（TB3側で robot.launch.py を起動しておくこと）"
fi

echo "[2/4] nav2 + 地図 起動..."
ros2 launch nav2_bringup bringup_launch.py use_sim_time:=False map:="$MAP" >$LOG/nav2.log 2>&1 & PIDS+=($!)

echo "[3/4] ROS-TCP-Endpoint 起動 (0.0.0.0:10000)..."
ros2 run ros_tcp_endpoint default_server_endpoint --ros-args -p ROS_IP:=0.0.0.0 >$LOG/endpoint.log 2>&1 & PIDS+=($!)

echo "    nav2起動待ち(28s)..."; sleep 28

echo "[4/4] Unity→nav2 ゴール中継 (nav2_unity_pipeline) 起動..."
ros2 run chapter5 nav2_unity_pipeline >$LOG/pipeline.log 2>&1 & PIDS+=($!)
sleep 3

echo "[RViz] 2D Pose Estimate用に起動 (ソフトGL)..."
LIBGL_ALWAYS_SOFTWARE=1 DISPLAY=:0 QT_X11_NO_MITSHM=1 ros2 run rviz2 rviz2 -d /opt/ros/humble/share/nav2_bringup/rviz/nav2_default_view.rviz >$LOG/rviz.log 2>&1 & PIDS+=($!)

echo ""
echo "=== 起動完了 ==="
echo "  このPCのIP : ${IP:-不明}   (Unity ROS Settings: ROS IP=${IP}, Port=10000, ROS2)"
echo "  Unity操作  : /goal_pose_unity にゴール送信 / initialpose自動送信"
echo "  ログ       : $LOG/*.log"
[ $REAL -eq 0 ] && echo "  ※オフライン: nav2はフル起動するがTB3が居ないので実移動はしない（配線確認まで）"
echo "  Ctrl+C で全停止"
echo ""
# 前面に留まってCtrl+Cを待つ（pipelineのログを流す）
tail -f $LOG/pipeline.log
