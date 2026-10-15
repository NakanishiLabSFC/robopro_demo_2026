#!/bin/bash
# TB3 bringup 停止 (バッテリー節約用)。起動は自分でSSHして ~/start_bringup.sh
#   接続設定は scripts/config.env (config.env.example をコピーして作る)
source "$(dirname "$0")/config.env" 2>/dev/null
TB3_USER="${TB3_USER:-ubuntu}"
TB3_IP="${TB3_IP:-192.168.3.9}"
TB3="${TB3_USER}@${TB3_IP}"

KILLCMD="sudo -S pkill -9 -f 'robot[.]launch'; sudo -S pkill -9 -x turtlebot3_ros; sudo -S pkill -9 -x ld08_driver; sudo -S pkill -9 -x robot_state_publisher; echo 'TB3 bringup停止OK'"

if [ -n "${TB3_PASSWORD:-}" ]; then
  # パスワード認証 (sshpass 経由)。sudo のパスワードも標準入力で渡す。
  sshpass -p "$TB3_PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$TB3" \
    "echo '$TB3_PASSWORD' | $KILLCMD" 2>/dev/null
else
  # 公開鍵認証 + パスワード無しsudo を想定
  ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$TB3" "sudo -n ${KILLCMD#sudo -S }" 2>/dev/null \
    || echo "  -> 停止失敗。scripts/config.env に TB3_PASSWORD を設定するか、公開鍵認証を設定してください。"
fi
