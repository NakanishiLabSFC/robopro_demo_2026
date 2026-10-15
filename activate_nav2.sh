#!/bin/bash
# nav2 の autostart が停滞して inactive のままの時に、全ライフサイクルノードを手動でactive化する保険。
# 症状: `ros2 lifecycle get /bt_navigator` が inactive、ゴールが拒否される。
# 原因: CPU競合等で lifecycle_manager の autostart が configure→activate に進めないことがある。
source /opt/ros/humble/setup.bash
source ~/vr_demo_ws/install/setup.bash
NODES="/map_server /amcl /controller_server /planner_server /smoother_server /behavior_server /bt_navigator /waypoint_follower /velocity_smoother"
echo "[activate_nav2] 各ノードをactiveへ..."
for n in $NODES; do
  st=$(timeout 4 ros2 lifecycle get $n 2>/dev/null)
  case "$st" in
    *active*) echo "  $n: 既にactive" ;;
    *inactive*) timeout 6 ros2 lifecycle set $n activate >/dev/null 2>&1 && echo "  $n: activate OK" || echo "  $n: activate 失敗" ;;
    *) echo "  $n: 状態取得不可（未起動?）" ;;
  esac
done
echo "[activate_nav2] 完了"
