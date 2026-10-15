#!/bin/bash
# 素のnav2_bringup を地図付きで起動（②構成: namespace無し, /goal_pose /initialpose）
# TB3実機/SLAM無しの疎通段階では use_sim_time:=False のまま。実機接続後に使用。
source /opt/ros/humble/setup.bash
source ~/vr_demo_ws/install/setup.bash
export TURTLEBOT3_MODEL=burger
MAP=~/vr_demo_ws/src/nav2_bringup_custom/maps/map.yaml
ros2 launch nav2_bringup bringup_launch.py use_sim_time:=False map:="$MAP"
