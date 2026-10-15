#!/bin/bash
# Unity ROS-TCP-Endpoint 起動（Unity⇔Ubuntu 疎通用）
# Unity側 ROS Settings: ROS IP = このPCのIP, Port=10000, Protocol=ROS2
source /opt/ros/humble/setup.bash
source ~/vr_demo_ws/install/setup.bash
echo "[endpoint] このPCのIP: $(ip -4 addr | grep -oP '(?<=inet\s)192\.168\.\d+\.\d+' | head -1)"
ros2 run ros_tcp_endpoint default_server_endpoint --ros-args -p ROS_IP:=0.0.0.0
