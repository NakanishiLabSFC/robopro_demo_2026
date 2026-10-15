#!/bin/bash
# 偽TF発行: 実機TB3が無い時、静的な map->odom->base_footprint(+base_link,scan) を出して
# nav2 の costmap を activate 可能にし、フルスタックをオフラインで立ち上げるためのヘルパー。
# ※実機TB3を使う時は起動しないこと（本物のodom/TFと競合する）。
# 用途: 段階3のFollowWaypoints受理確認 / RVizで軌跡+ロボット原点表示 のオフライン検証。
source /opt/ros/humble/setup.bash
echo "[fake_tf] 静的TF map->odom->base_footprint->base_link->base_scan を発行（TB3が来たら止める）"
ros2 run tf2_ros static_transform_publisher 0 0 0 0 0 0 map odom &
ros2 run tf2_ros static_transform_publisher 0 0 0 0 0 0 odom base_footprint &
ros2 run tf2_ros static_transform_publisher 0 0 0 0 0 0 base_footprint base_link &
ros2 run tf2_ros static_transform_publisher 0 0 0.1 0 0 0 base_link base_scan &
wait
