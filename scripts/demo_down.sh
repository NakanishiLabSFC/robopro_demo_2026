#!/bin/bash
# =========================================================
# VR / 地上絵デモ  PC側スタック停止 (nav2/endpoint/pipeline/generator/RViz)
#   ※ TB3 bringup は止めない(手動管理)。止めたいなら tb3 でSSHして pkill、
#      またはバッテリー節約したいときは tb3stop エイリアス使用。
#   エイリアス: demodown
# =========================================================
source /opt/ros/humble/setup.bash 2>/dev/null

echo "======== デモ停止 [PC側] ========"
# PCスタック正常終了(cleanup trapでRVizも閉じる)
SPID=$(pgrep -f 'run_nav_demo.sh|run_geoglyph_demo.sh')
[ -n "$SPID" ] && kill -TERM $SPID 2>/dev/null
sleep 3
# 残りをPID指定で掃除(スクリプト内なので自己マッチしない)
PIDS=$(pgrep -f 'component_container_isolated|default_server_endpoint|nav2_unity_pipeline|geoglyph_generator|waypoint_sender|static_transform_publisher')
[ -n "$PIDS" ] && kill -9 $PIDS 2>/dev/null
pkill -9 -x rviz2 2>/dev/null
echo "  -> PCスタック/RViz 停止"
echo "  (TB3 bringupは稼働継続。止めるなら tb3stop か、tb3でSSHして手動)"
echo "======== 停止完了 [PC側] ========"
