# TB3をキャンパス網(133.27.x)からWavlinkローカル網(192.168.12.x)へ移す手順

目的: TB3を **192.168.12.50** に固定し、PC(192.168.12.159)と同一サブネットにして実機DDSデモを成立させる。
作業場所: **TB3本体**(micro-HDMI + キーボード)。SSHは使わない(切れないので安全)。
ログイン: user `ubuntu` / pass は研究室メンバーに確認 (リポジトリには載せない)

---

## 手順

### 1. ログインして現状を控える（後で戻せるように）
```bash
# Wi-Fi IF名(たぶん wlan0)と現在のIPを確認
ip -4 addr show
# 接続管理がNetworkManagerかnetplanか判定
nmcli device status        # ここで wlan0 が "connected" と出れば NetworkManager 管理 → 方法A
ls /etc/netplan/            # *.yaml があり上でNMでなければ → 方法B
```
> `nmcli device status` がちゃんと表示されれば **方法A(nmcli)** を使う。エラーなら **方法B(netplan)**。

---

### 方法A: NetworkManager (nmcli) の場合 ← 推奨・簡単・戻しやすい
```bash
# 接続プロファイル名を確認(例: "203A-Wavlink-5G")
nmcli -t -f NAME,DEVICE connection show --active

# ↓ CONNは上で出たWi-Fi接続名に置き換える
CONN="203A-Wavlink-5G"

# 静的IPに設定
nmcli connection modify "$CONN" ipv4.method manual \
  ipv4.addresses 192.168.12.50/24 \
  ipv4.gateway 192.168.12.1 \
  ipv4.dns "192.168.12.1 8.8.8.8"

# 反映(再接続)
nmcli connection down "$CONN" && nmcli connection up "$CONN"
```

**元に戻す場合(DHCPへ):**
```bash
nmcli connection modify "$CONN" ipv4.method auto ipv4.addresses "" ipv4.gateway "" ipv4.dns ""
nmcli connection down "$CONN" && nmcli connection up "$CONN"
```

---

### 方法B: netplan の場合
```bash
# 既存設定をバックアップ
sudo cp /etc/netplan/*.yaml ~/netplan_backup.yaml

# 設定ファイルを編集(ファイル名は ls /etc/netplan/ で確認)
sudo nano /etc/netplan/50-cloud-init.yaml
```
wifis の該当SSIDブロックを以下のように（SSID名とパスワードは既存に合わせる）:
```yaml
network:
  version: 2
  wifis:
    wlan0:
      dhcp4: no
      addresses: [192.168.12.50/24]
      routes:
        - to: default
          via: 192.168.12.1
      nameservers:
        addresses: [192.168.12.1, 8.8.8.8]
      access-points:
        "203A-Wavlink-5G":
          password: "Nakanishi3296"
```
反映:
```bash
sudo netplan apply
```
**元に戻す:** `sudo cp ~/netplan_backup.yaml /etc/netplan/50-cloud-init.yaml && sudo netplan apply`

---

### 2. 成功確認（TB3本体で）
```bash
ip -4 addr show wlan0            # 192.168.12.50 になっていればOK
ping -c3 192.168.12.159         # ← PC に届けば同一サブネット成功！(最重要)
ping -c3 8.8.8.8                # ← インターネットも生きてるか(Claude生成用)
```
- `192.168.12.159` に ping が通ったら **勝ち**。PCと同じ島に入れた。
- インターネットpingも通れば、TB3側でネットが要る作業も可能。

### 3. ROS_DOMAIN_ID は触らなくてOK
TB3は `ROS_DOMAIN_ID=30` のまま放置でよい。**PC側スタックを私がdomain 30で起動し直して合わせます**。

---

## 終わったら私に伝えること
- `ip -4 addr show wlan0` の結果（192.168.12.50 になったか）
- `ping 192.168.12.159` が通ったか
これを聞いたら、私が PCスタックを domain 30 で再起動 → DDS疎通テスト → nav2実機テストへ進めます。

## 注意
- **micro-HDMIで本体作業なので、設定を間違えても画面から直せる**（SSHと違い切れて詰むことはない）。安心して試してOK。
- もし 192.168.12.50 が既に誰かに使われてたら .51, .52 等に変える。
