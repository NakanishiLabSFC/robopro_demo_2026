#!/bin/bash
source /opt/ros/humble/setup.bash
source /home/ubuntu/vr_demo_ws/install/setup.bash 2>/dev/null
export ROS_DOMAIN_ID=30
export TURTLEBOT3_MODEL=burger
exec ros2 run turtlebot3_teleop teleop_keyboard
