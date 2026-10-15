# vr_demo_ws — Unity/Quest × ROS 2 × TurtleBot3 デモ（Ubuntu PC側）

Quest のコントローラで指した床へ実機 TurtleBot3 を走らせる **VRゴール送信デモ**と、
お題テキストから生成AIが軌跡を作り TB3 が床に絵を描く **地上絵デモ**の、**Ubuntu PC（ROS 2）側**の実装。

実機動作確認済み（2026-07-11、研究室）: Unity からのゴール送信で実機 TB3 が走行、RViz からのナビ、
地上絵の軌跡生成〜waypoint 送信まで全チェーン疎通。

> **このリポジトリは Ubuntu PC 側だけです。** Unity（Windows）側のプロジェクトは別管理です。
> PC 側から渡した C# スクリプトと引き継ぎ書は `unity/` と `docs/` に入っています。

---

## 全体構成

```
┌─────────────┐  QuestLink  ┌──────────────────┐   TCP:10000   ┌──────────────────────┐
│ Quest HMD   │────────────>│ Windows PC       │──────────────>│ Ubuntu PC (このリポ)  │
│ コントローラ │             │ Unity 2021.3     │  ROS-TCP      │ Nav2 + Endpoint      │
└─────────────┘             └──────────────────┘   Endpoint    └──────────┬───────────┘
                                                                          │ Wi-Fi / DDS
                                                                          │ ROS_DOMAIN_ID=30
                                                                   ┌──────▼───────┐
                                                                   │ TurtleBot3    │
                                                                   │ (RasPi/Humble)│
                                                                   └───────────────┘
```

### ① VRゴール送信デモ
```
Unity (床をクリック/指す)
  → /goal_pose_unity (PoseStamped, frame=map)
  → nav2_unity_pipeline        … NavigateToPose アクションへ転送（フィードバック/キャンセル対応）
  → /navigate_to_pose → Nav2 → /cmd_vel → 実機TB3 が走行
```

### ② 地上絵デモ（拡張・自作）
```
Unity (お題テキスト "ヨット")
  → /draw_request (String)
  → geoglyph_generator          … Claude API で座標列を構造化出力 → map座標へ変換
  → /geoglyph_path (Path, frame=map)    … Unity は LineRenderer で軌跡プレビュー
  → /execute_geoglyph (Bool)    … Unity の実行トリガ
  → waypoint_sender             … 表示用の密なPathを nav2 用に間引き（既定40WP）
  → /follow_waypoints (FollowWaypoints) → Nav2 → 実機TB3 が巡回描画
```

APIキーが無い場合、`geoglyph_generator` は自動で **MOCKモード**（円/星/ハート/四角/うずまきの手続き生成）に
切り替わるので、オフラインでも検証できます。

---

## ディレクトリ構成

| パス | 内容 |
|---|---|
| `src/geoglyph/` | **自作**。地上絵パッケージ（`geoglyph_generator` / `waypoint_sender`） |
| `src/chapter5/` | `nav2_unity_pipeline`（Unityのゴールを Nav2 アクションへ転送）。書籍サンプル由来 |
| `src/nav2_bringup_custom/` | 地図（`maps/`）と Nav2 パラメータ、launch |
| `src/ROS-TCP-Endpoint/` | **未コミット**。Unity 公式の TCP エンドポイント（下記手順で clone） |
| `run_nav_demo.sh` | ①VRデモ一式を起動（fake_tf + nav2 + endpoint + pipeline + RViz） |
| `run_geoglyph_demo.sh` | ②地上絵デモ一式を起動（fake_tf + nav2 + endpoint + generator + sender + RViz） |
| `run_nav2.sh` / `run_endpoint.sh` / `run_geoglyph.sh` | 個別起動（デバッグ用） |
| `fake_tf.sh` | **TB3が無いとき専用**。静的TFを流して Nav2 をフル起動させる（実機時は使わない） |
| `activate_nav2.sh` | waypoint_follower だけを強制 activate する応急策 |
| `scripts/demo_up.sh` | ワンコマンド起動（受信確認 → 時刻同期 → スタック起動 → 初期姿勢発行） |
| `scripts/demo_down.sh` | PC側スタック停止（TB3 bringup は止めない） |
| `scripts/tb3stop.sh` | TB3 の bringup 停止（バッテリー節約用） |
| `scripts/teleop30.sh` | キーボード teleop（地図作成時の手動運転用） |
| `unity/` | PC側で書いて Windows に渡した C#（`GeoglyphController.cs`, `EditorDebugGoalSender.cs`） |
| `docs/` | 設計書・引き継ぎ書・TB3固定IP手順 |

### 地図（`src/nav2_bringup_custom/maps/`）

| ファイル | サイズ | origin | 備考 |
|---|---|---|---|
| `map_sfc.yaml` | 158×183 px (≈7.9×9.2 m) | `[-1.44, -3.34]` | **現在の既定**（`run_*_demo.sh` が参照） |
| `room_map.yaml` | 127×130 px (≈6.35×6.5 m) | `[-1.78, -1.82]` | 研究室を Cartographer で作成（2026-07-11） |
| `map.yaml` | 114×141 px (≈5.7×7.0 m) | `[-2.15, -3.25]` | 初期の流用地図 |

地図を差し替えたら **Unity 側の `MapTransformer`（pixelSize / resolution / origin）も合わせて更新**が必要です。

---

## セットアップ

前提: Ubuntu 22.04 + ROS 2 Humble + Nav2 + TurtleBot3 パッケージ

```bash
git clone <このリポジトリ> ~/vr_demo_ws
cd ~/vr_demo_ws

# 1) Unity 公式 TCP エンドポイント（ROS 2 ブランチ）を取得
git clone -b main-ros2 https://github.com/Unity-Technologies/ROS-TCP-Endpoint.git src/ROS-TCP-Endpoint

# 2) 地上絵デモで Claude API を使う場合（任意。未設定なら MOCK で動く）
cp api_key.env.example api_key.env
#   api_key.env を編集して実キーを入れる
chmod 600 api_key.env

# 3) TB3 の接続情報
cp scripts/config.env.example scripts/config.env
#   TB3_IP / TB3_PASSWORD / PC_IP を自分の環境に合わせる

# 4) anthropic パッケージ（地上絵デモで Claude を使う場合）
pip install anthropic

# 5) ビルド
colcon build --symlink-install
source install/setup.bash
```

`~/.bashrc` の末尾に以下を入れておくと毎回の export が不要になります
（**ROS_DOMAIN_ID は複数定義されていると最後の行が勝つ**ので末尾に置くこと）:

```bash
export ROS_DOMAIN_ID=30          # TB3 側が 30 固定なので合わせる
export TURTLEBOT3_MODEL=burger
source ~/vr_demo_ws/install/setup.bash

alias vrup='bash ~/vr_demo_ws/scripts/demo_up.sh nav'   # ①VRゴールデモ
alias geoup='bash ~/vr_demo_ws/scripts/demo_up.sh geo'  # ②地上絵デモ
alias demodown='bash ~/vr_demo_ws/scripts/demo_down.sh'
alias tb3stop='bash ~/vr_demo_ws/scripts/tb3stop.sh'
```

---

## 実行手順（実機）

```bash
# 1) TB3 に SSH して bringup を起動（★必ず1個だけ）
ssh ubuntu@<TB3_IP>
  ~/start_bringup.sh        # LDS_MODEL=LDS-02 が必要

# 2) PC 側スタックを起動
vrup        # ①VRゴールデモ      （または geoup で②地上絵デモ）

# 3) 自動起動した RViz で [2D Pose Estimate] を使い、
#    LiDAR スキャンが壁と重なるように自己位置を合わせる  ★ここが一番重要

# 4) デモ
#    ① Quest で床を指す → TB3 が移動
#    ② Unity でお題を送信 → 軌跡プレビュー → 実行 → 巡回描画

# 5) 停止
demodown    # PC側のみ（TB3 bringup は動き続ける）
tb3stop     # TB3 の bringup も止める（バッテリー節約）
```

Unity の **ROS Settings**: `IP = PC側のIP` / `Port = 10000` / Protocol = `ROS2`

### TB3 無しで動かす（オフライン検証）

```bash
bash run_nav_demo.sh          # --real を付けない = fake_tf が入りフル起動
bash run_geoglyph_demo.sh     # 同上
```

### 地上絵のチューニング

```bash
NUM_WAYPOINTS=60 INSET=0.05 TARGET_POINTS=120 bash run_geoglyph_demo.sh --real
```
- `TARGET_POINTS`（既定100）… 生成する点数＝表示密度
- `NUM_WAYPOINTS`（既定40）… Nav2 に送る間引き後のWP数。**多すぎると各WPのゴール許容誤差で絵がガタつき遅くなる**
- `INSET`（既定0.15）… 地図端の余白。小さくすると絵が大きくなる

---

## ハマりどころ（実機で踏んだもの）

| 症状 | 原因と対処 |
|---|---|
| `turtlebot3_ros` が `exit -6` で死ぬ | **bringup の二重起動**。`/dev/ttyACM0`（OpenCR）を奪い合う。全部kill して1個だけ起動 |
| 走行し始めた瞬間に `There is no status packet` → `stack smashing` | モータ基板の通信断。**走行負荷で再現**。アダプタ給電だと電流不足で落ちる → **充電済みLiPoで駆動**。OpenCRのケーブルも疑う |
| ログに `Failed connection with Devices` | OpenCR のUSBは繋がっているがモータ主電源OFF/バッテリ切れ → OpenCR の電源スイッチON |
| Nav2 が全ノード inactive でゴールを拒否 | TB3 が無いと `controller_server` の local_costmap が `odom→base_footprint` TF を待って activate でブロックする → `fake_tf.sh`（実機時は**使わない**） |
| Nav2 TF の extrapolation エラー | **TB3 とPCの時刻ズレ**。`demo_up.sh` が自動同期。TB3 を 100〜150ms 進み側に置くとエラーが消える |
| ゴールが即 "Reached" / 動かない | 自己位置ズレ。必ず 2D Pose Estimate でスキャンを壁に合わせる。`xy_goal_tolerance=0.25m` なので近すぎるゴールも即到達扱い |
| RViz に地図が出ない | GLSL `indexed_8bit_image` シェーダの不具合 → `LIBGL_ALWAYS_SOFTWARE=1` で起動（`run_*.sh` は対応済み） |
| `/draw_request` の Subscription count が 0 | 古い/混在スタックが残っている → `demodown` してから `geoup` でクリーン起動 |
| `pkill -f <pattern>` でシェルごと落ちる | コマンド文字列自体にパターンが含まれ自分を殺す → `pkill -x`（プロセス名完全一致）か PID 直kill、またはスクリプト経由で実行 |
| `set -u` 下で ROS の `setup.bash` を source すると即 exit 1 | `AMENT_TRACE_SETUP_FILES` が未定義 → source 行を `set +u` / `set -u` で囲む（対応済み） |
| DDS が繋がらない | ①`ROS_DOMAIN_ID` を PC/TB3 で一致させる（30）②同一サブネットにする（Wi-Fiのマルチキャストが不安定なので別サブネットは不可）。`ros2 daemon stop && ros2 daemon start` で安定する |

**①VRデモと②地上絵デモは別スタックで、同時起動できません**（nav2 とポート10000が競合）。切り替えるときは必ず `demodown` を先に。

---

## 備考

- TB3 burger は**カメラ非搭載**のため FPV 映像は未対応。将来付けるなら `v4l2_camera`(USB) か
  `camera_ros`(CSI) で `/image_raw/compressed` を domain 30 に出せば、Endpoint 経由で Unity から購読できます。
- 新しい部屋で使うときは `scripts/teleop30.sh` で手動運転しながら
  `turtlebot3_cartographer` で地図を作り、`nav2_map_server map_saver_cli` で保存してください。
- **秘密情報はコミットしていません**。`api_key.env` と `scripts/config.env` は `.gitignore` 済みで、
  各自 `.example` からコピーして作ってください。
