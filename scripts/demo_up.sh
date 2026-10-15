#!/bin/bash
# =========================================================
# VR / 地上絵デモ  PC側ワンコマンド起動
#   ※ TB3 bringup は自分でSSHして手動起動しておくこと(このスクリプトには含めない)
#       ssh ubuntu@<TB3_IP>  ->  ~/start_bringup.sh
#   使い方:  bash scripts/demo_up.sh nav   # VR単発ゴール(Quest→移動)
#            bash scripts/demo_up.sh geo   # 地上絵(お題→描画)
#   エイリアス: vrup / geoup    停止: demodown
#   接続設定: scripts/config.env (config.env.example をコピーして作る)
# =========================================================
MODE="${1:-nav}"
WS="$(cd "$(dirname "$0")/.." && pwd)"
source "$(dirname "$0")/config.env" 2>/dev/null
TB3_USER="${TB3_USER:-ubuntu}"
TB3_IP="${TB3_IP:-192.168.3.9}"
TB3="${TB3_USER}@${TB3_IP}"
export ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-30}"
export TURTLEBOT3_MODEL=burger
export DISPLAY=:0
source /opt/ros/humble/setup.bash
source "$WS/install/setup.bash" 2>/dev/null

echo "======== デモ起動 [PC側のみ] (mode=$MODE, domain=$ROS_DOMAIN_ID) ========"
echo "  ※ TB3 bringup は事前にSSHで起動済みの前提 (~/start_bringup.sh)"

echo "[1/3] TB3トピック受信確認 (bringup稼働してるか)..."
if timeout 8 ros2 topic list 2>/dev/null | grep -q '/scan'; then
  echo "  -> /scan 受信OK (bringup稼働中)"
  # nav2のTF安定用に時刻だけ軽く合わせる(SSH1回, 失敗してもスキップ)
  # TB3を少し「進み側」に置くとTFの未来外挿エラーが出にくい
  EPOCH=$(python3 -c "import time;print(f'{time.time()+0.6:.3f}')")
  if [ -n "${TB3_PASSWORD:-}" ]; then
    sshpass -p "$TB3_PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=6 "$TB3" \
      "echo '$TB3_PASSWORD' | sudo -S date -s '@$EPOCH' >/dev/null 2>&1" \
      && echo "  -> 時刻同期OK" || echo "  -> 時刻同期スキップ"
  else
    echo "  -> 時刻同期スキップ (scripts/config.env に TB3_PASSWORD 未設定)"
  fi
else
  echo "  -> ★/scan未受信! 先にTB3でbringupを起動してください (ssh $TB3 -> ~/start_bringup.sh)"
  echo "     ...それでも続行します(bringup後に再度 vrup してもOK)"
fi

echo "[2/3] PCスタック起動..."
if [ "$MODE" = "geo" ]; then SCRIPT=run_geoglyph_demo.sh; else SCRIPT=run_nav_demo.sh; fi
setsid bash "$WS/$SCRIPT" --real </dev/null >/tmp/${MODE}_demo_run.log 2>&1 &
disown
echo "  -> $SCRIPT (--real) 起動中... nav2待ち 38s"
sleep 38

echo "[3/3] 初期姿勢 (map 0,0,0) 発行..."
# --once だと購読前に終わって届かないので -r で連続pubする
timeout 6 ros2 topic pub -r 3 /initialpose geometry_msgs/msg/PoseWithCovarianceStamped \
  '{header: {frame_id: "map"}, pose: {pose: {position: {x: 0.0, y: 0.0, z: 0.0}, orientation: {w: 1.0}}, covariance: [0.25,0,0,0,0,0, 0,0.25,0,0,0,0, 0,0,0,0,0,0, 0,0,0,0,0,0, 0,0,0,0,0,0, 0,0,0,0,0,0.068]}}' >/dev/null 2>&1

echo ""
echo "======== 起動完了 [PC側] ========"
echo "  Unity ROS Settings: IP=${PC_IP:-<このPCのIP>} / Port=10000 / ROS2"
echo "  RViz(自動起動済) で 2D Pose Estimate -> 自己位置合わせ"
if [ "$MODE" = "geo" ]; then
  echo "  地上絵: Unityでお題送信 -> 軌跡表示 -> Space(実行) で描画巡回"
else
  echo "  VR: Questで床を指す -> TB3が移動"
fi
echo "  停止: demodown"
