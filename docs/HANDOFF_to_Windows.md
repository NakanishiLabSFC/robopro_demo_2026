# 引き継ぎ書 — VRゴール送信デモ（Ubuntu側 → Windows側 Claude Code へ）

作成: 2026-07-06 夜 / 作成者: Ubuntu側 Claude Code
対象読者: **Windows側の Claude Code（あなた）**。このファイルはUbuntu機からダウンロードして持ち込んだものです。

---

## 0. これは何のプロジェクトか

書籍『UnityとROS 2で実践するロボットプログラミング』第7章の再現。
**Quest HMDのコントローラで指した床の位置へ、実機TurtleBot3(TB3)を移動させるVRデモ**を作る。
指示書の原本は `CLAUDE.md`（Ubuntu機の ~/Downloads にある。必要なら別途渡す）。

### システム構成
```
TB3 (RasPi, ROS2 Humble) ←Wi-Fi→ Ubuntu PC (Nav2 + ros_tcp_endpoint + pipeline)
                                        ↑ TCP :10000
                                  Windows PC (Unity 2021.3.26f1) ←Quest Link→ Quest 2/3
```
- **Ubuntu側 = Phase 2（ROS2/Nav2/受信側）** … 下記の通り**構築・検証ほぼ完了**
- **Windows側 = Phase 1（Unity/送信側）… ここがあなたの担当。ほぼ未着手**
- リポジトリ: https://github.com/NakanishiLabSFC/unity-ros2-robot-programming.git
  Unity側は `chapter7/Chapter7Project`（Unity 2021.3.26f1、シーン `Assets/Scenes/Chapter7_VR.unity`）

---

## 1. Ubuntu側で完了済みのこと（あなたは触らなくてよい）

| 項目 | 状態 |
|---|---|
| ROS2 Humble / colcon / nav2 / turtlebot3 導入 | ✅ 既存 |
| `~/vr_demo_ws` 構築・ビルド（nav2_bringup_custom + ROS-TCP-Endpoint + chapter5 pipeline） | ✅ 成功 |
| ros_tcp_endpoint 起動 → ポート10000 LISTEN | ✅ 確認済 |
| 素のnav2_bringup + 地図ロード（map_server active, /map 配信） | ✅ 確認済 |
| **loopback疎通**（偽goal → pipeline → nav2アクション受理） | ✅ 確認済（TB3無しで検証） |

**Ubuntu PCのIP: `192.168.3.247`** ← Unity側 ROS Settings の ROS IP にこれを入れる。

Ubuntu側の起動コマンド（本番/疎通テスト時、ターミナル3枚）:
```bash
# T1: エンドポイント
bash ~/vr_demo_ws/run_endpoint.sh
# T2: nav2 + 地図
bash ~/vr_demo_ws/run_nav2.sh
# T3: Unity→nav2 ゴール中継ノード
source ~/vr_demo_ws/install/setup.bash && ros2 run chapter5 nav2_unity_pipeline
```

---

## 2. 重要な設計判断（Windows側の設定に直結）

### 2-1. ゴールは「pipeline経由（アクション）」で送る
本家は Unity → トピック `goal_pose_unity` → `nav2_unity_pipeline.py`（chapter5）が
NavigateToPoseアクション `navigate_to_pose` でnav2へ転送する設計。
このアクション名は namespace無しで素のnav2の `/navigate_to_pose` と一致するため、
**custom nav2（robot1 namespace前提）は使わず、素のnav2_bringup + 地図yamlだけ流用**する方針。
→ フィードバック/キャンセル対応で堅牢、かつUnity側の設定変更が最小。

### 2-2. トピック名（Unity Inspector の GoalPublisher）
シーンの既定値を確認済み。**基本そのままでよい**:
- `goalTopicName` = `goal_pose_unity` ← **既定のまま。変更不要**
- `initialPoseTopicName` = `/initialpose` ← 既定のまま。amclが直接購読
- `sendInitialPoseOnStart` = 1（Start時に原点initialposeを自動送信）

### 2-3. 地図はpngテクスチャ（pgm不要・Gazebo不要）
- Nav2側は `map.pgm`+`map.yaml`（Ubuntu側にある）。
- **Unity側は画像テクスチャ `Assets/Textures/map.png`（114×141px、既にリポジトリにある）** を床に貼るだけ。
- `MapTransformer` コンポーネントの Inspector 値（map.yaml由来）:
  - `pixelSize` = (114, 141)
  - `resolution` = 0.05
  - `origin` = (-2.15, -3.25)
- 本番の教室地図が要るときは Gazeboではなく**実機TB3で教室をSLAM**して作る（Phase 3、研究室で）。それまではサンプル地図で全工程を組める。

---

## 3. Windows側（あなた）のToDo = Phase 1

CLAUDE.md の Phase 1 に沿う。GUI操作はユーザー(Hyu)に1ステップずつ指示すること。

1. **Unity 2021.3.26f1 + Android Build Support** をインストール（DL最遅なので最優先で着手させる）
2. **Meta Quest Link (PC版)** をインストール（ペアリングは実機合流後）
3. リポジトリを clone → Unity Hub で `chapter7/Chapter7Project` を開く
   - 初回コンパイルエラー多発は正常（`Assets/Oculus` がgitignoreされているため）
4. **Oculus Integration (deprecated, v57前後)** を Package Manager → My Assets → Import
   - ダイアログは基本 Yes/Upgrade/Restart（OVRPlugin更新→再起動）。コンパイルエラーゼロを確認
   - ※ Meta XR All-in-One SDK（新SDK）は参照が壊れるため**使用禁止**
5. **`Chapter7_VR.unity` のMissing参照修復**（シーンはテキストYAML。あなたが直接読んで切り分け、ユーザーにInspector操作を指示）
   - OVRCameraRig Missing → `Oculus/VR/Prefabs/OVRCameraRig` 再配置、Tracking Origin = Floor Level
   - ControllerRayHit: rayOrigin=RightHandAnchor / rayCastHitPointObj=Prefabs/RayCastHitPoint / collisionLayer=床レイヤー
   - SetGoal: directionIndicatorPrefab / goalMarkerPrefab / getLaserPosition / goalPublisher
   - GoalPublisher: setGoal
   - **要確認**: `Map.mat` がテクスチャ未割り当ての疑い（`m_Texture: 0`）。空なら `Textures/map.png` をAlbedoに割り当てる
   - XR Plug-in Management → PC: Oculus にチェック
6. **Robotics → ROS Settings**: ROS IP = `192.168.3.247`、Port=10000、Protocol=ROS2
7. **デバッグ用スクリプトの設置**（下記セクション4。ファイルは持ち込み済み）

### Phase 1 完了条件
- [ ] コンパイルエラーゼロ
- [ ] Play → Gameビューに地図の床が表示される（HMD無しでOK）
- [ ] EditorDebugGoalSender でクリック→Consoleにgoal座標が出る（ROS未接続エラーは正常）

---

## 4. 持ち込み済みファイル: EditorDebugGoalSender.cs

HMD無しでゴール送信を検証するための**エディタ専用デバッグスクリプト**。Ubuntu側で作成済み、
このファイルと一緒に `EditorDebugGoalSender.cs` を持ち込んでいる（同じUSB/DL元にあるはず）。

- 役割: Unity再生中に**Gameビューを左クリック → メインカメラからレイ → 床の衝突点をゴールとして送信**。
  QuestコントローラのSetGoalと同じ FLU変換・同じトピック(`goal_pose_unity`)・同じ PoseStamped を使う。
- **既存の本のファイルは一切改変していない**（自己完結型。SetGoal/GoalPublisherは無傷）。`#if UNITY_EDITOR`付きでビルドには含まれない。

### 設置手順
1. `EditorDebugGoalSender.cs` を `Assets/Scripts/` に置く（Unityが自動コンパイル）
2. シーンの空GameObject（GoalPublisherが付いたオブジェクトでよい）にコンポーネント追加
3. Inspector:
   - `Goal Topic Name` = `goal_pose_unity`（デフォルト入力済）
   - `Collision Layer` = 床レイヤー（ControllerRayHitのcollisionLayerと同じ）
   - `Ray Camera` = 空ならMainCamera自動
   - `Goal Yaw Degrees` = 0 でよい
4. 疎通確認後は**チェックを外して無効化**（本番のマウス誤爆防止）
5. 注意: 地図オブジェクトに床のCollider（Mesh/Box）が無いとクリックが当たらない

---

## 5. 疎通テスト手順（HMD無し・Windows準備でき次第）

1. Ubuntu側で T1/T2/T3（セクション1のコマンド）を起動
2. Unity Play → Robotics→ROS Settings→Show HUD が「接続(緑)」になるか確認
   - つながらない: ping 192.168.3.247 → Windowsファイアウォールの送信10000/TCP → IP再確認
3. Gameビューの地図の床を左クリック（EditorDebugGoalSender）
4. Ubuntu側で `ros2 topic echo /goal_pose_unity` にゴールが出れば **Unity→Ubuntu 疎通成功**
5. pipelineログに `Received New Goal` / `Sending Goal` が出れば中継もOK
   （TB3が無い間はnav2が「ロボット位置なし」で経路計画まで進まないのは正常。実機接続で解消）

---

## 6. まだ出来ていないこと / Phase 3（実機合流後、研究室）

- [ ] TB3実機接続 → RVizでNav2単体動作（2D Pose Estimate → 2D Goal Pose）
- [ ] Unityクリック送信でTB3が実際に動く
- [ ] Quest Link接続 → HMDでレイ/トリガー/スティック動作
- [ ] フルデモ（実機初期位置を地図原点に置いてPlay → initialpose自動送信）

### トラブルシューティング要点
| 症状 | 対処 |
|---|---|
| HUD未接続 | ping / Windowsファイアウォール10000 / エンドポイント再起動 |
| goal送ってもTB3無反応 | `ros2 topic echo` で受信確認 → 届いてる:nav2 autostart/ライフサイクル、届いてない:トピック名不一致 |
| Unity内TB3位置ずれ | MapTransformer値と地図yaml不一致 / initialposeと実機初期位置不一致 |
| テレポートマーカー不可視 | XR設定 Stereo Rendering Mode = Multi Pass |

---

## 7. 注意（Ubuntu側で気づいた点）

- リポジトリの chapter4 / chapter5 には**以前からの改変**が入っている（Ubuntu側Claude Codeの作業ではない）。
  chapter7（本デモ）には影響しないが、気になるなら `git status` で確認可。chapter7の既存ファイルは無改変（本のママ）。

以上。まずは Phase 1（Unity導入〜シーン修復）から。GUI操作はユーザーに具体的に指示してあげてください。
