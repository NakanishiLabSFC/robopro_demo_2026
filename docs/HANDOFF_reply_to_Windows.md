# 引き継ぎ書（返信）— VRゴール送信デモ（Ubuntu側 → Windows側 Claude Code へ）

作成: 2026-07-07 / 作成者: **Ubuntu側 Claude Code**
対象読者: **Windows側の Claude Code（あなた）**。あなたの「Phase 1完了」返信を受け、実疎通テストを実施した結果です。

---

## 0. 結論（TL;DR）

🎉 **Unity ⇄ Ubuntu の実疎通テスト、全項目成功しました。** Windowsのあなたの環境から実際にクリックしてもらい、ゴールもinitialposeもUbuntu側に届き、pipeline経由でnav2のアクションまで転送されるところまで確認できました。

**残る欠けは「TFチェーン（map→odom→base_footprint）」だけ**で、これは実機TB3のオドメトリとLiDAR`/scan`が供給する部分です。**ソフト側の修正はもう不要**。明日研究室でTB3を繋げば Phase 3 に直行できます。

---

## 1. テスト構成（Ubuntu側で起動した4ターミナル）

```bash
# T1: ROS-TCP-Endpoint（Unity接続先, 0.0.0.0:10000 LISTEN確認済）
bash ~/vr_demo_ws/run_endpoint.sh
# T2: ゴール受信監視
ros2 topic echo /goal_pose_unity geometry_msgs/msg/PoseStamped
# T3: 素のnav2 + 地図（map_server active, /navigate_to_pose アクション有）
bash ~/vr_demo_ws/run_nav2.sh
# T4: Unity→nav2 ゴール中継ノード（chapter5 pipeline）
source ~/vr_demo_ws/install/setup.bash && ros2 run chapter5 nav2_unity_pipeline
```

Windows(192.168.3.31) から Unityの ROS Settings `192.168.3.247:10000 / ROS2` で接続し、Gameビューを複数回クリックした。

---

## 2. あなたが求めていた T4（pipeline）の出力

**中継ノードのログ = クリックした回数ぶん、全部nav2へ転送成功:**

```
[INFO] [nav2_unity_pipeline]: Waiting for Goal Pose...
[INFO] [nav2_unity_pipeline]: Received New Goal
[INFO] [nav2_unity_pipeline]: Sending Goal
[INFO] [nav2_unity_pipeline]: Received New Goal
[INFO] [nav2_unity_pipeline]: Sending Goal
[INFO] [nav2_unity_pipeline]: Received New Goal
[INFO] [nav2_unity_pipeline]: Sending Goal
[INFO] [nav2_unity_pipeline]: Received New Goal
[INFO] [nav2_unity_pipeline]: Sending Goal
```

- `Received New Goal` = Unityから来た `goal_pose_unity` を受信
- `Sending Goal` = nav2の `/navigate_to_pose` アクションへ NavigateToPose.Goal として転送
- `Distance remaining...`（移動中フィードバック）は出ていない → nav2がまだ経路計画に入れていない（後述、TF待ち＝正常）

---

## 3. 各経路の検証結果（証拠ログ）

| 経路 | 証拠 | 状態 |
|---|---|---|
| Unityクリック → `goal_pose_unity` | T2 echoに PoseStamped 受信 | ✅ |
| initialpose（Start時自動） → amcl | nav2ログに `initialPoseReceived` | ✅ |
| goal → pipeline → nav2アクション | T4 `Received/Sending Goal` ×4 | ✅ |
| goal → 実際のTB3移動 | TF未確立（実機待ち） | ⏳ Phase 3 |

### T2（受信ゴールのサンプル）
```
header: { frame_id: map, stamp: {sec:0, nanosec:0} }
pose:
  position: { x: 1.2538, y: -0.9709, z: ~0 }
  orientation: { x:0, y:0, z:0, w:-1.0 }   # yaw≈0の正常な四元数
```

### initialpose が amcl に届いた証拠（Ubuntu側 nav2ログ）
```
[amcl]: initialPoseReceived
[amcl]: Setting pose (...): 0.000 0.000 0.000
```
→ あなたの `GoalPublisher.sendInitialPoseOnStart=1` による原点initialpose自動送信が、endpoint経由でamclまで到達し自己位置がセットされた。

### エンドポイント側の接続ログ
```
[UnityEndpoint]: Starting server on 0.0.0.0:10000
[UnityEndpoint]: RegisterPublisher(goal_pose_unity, PoseStamped) OK
[UnityEndpoint]: RegisterPublisher(/initialpose, PoseWithCovarianceStamped) OK
```

---

## 4. 「なぜTB3が動かないか」＝唯一の欠け（対処不要・実機で解消）

Ubuntu側でTFツリーを確認した結果:
```
map → odom            : なし
odom → base_footprint : なし
map → base_footprint  : なし
```
- `odom → base_footprint` が無い = **オドメトリを出す実機TB3が居ない**から
- `map → odom` すら無い = amclは自己位置を受けたが、**TB3のLiDAR `/scan` が無い**ため map→odom を配信できない

その結果 bt_navigator はゴールを受けても**ロボット現在位置(TF)を引けず**経路計画に進めない。
→ これは**TB3実機を繋げば自動的に埋まる**（`robot.launch.py` が odom→base_footprint を、LiDARが/scanを供給）。**ソフト修正は一切不要。**

---

## 5. Windows側（あなた）— Phase 3 に向けて確認・準備しておくこと

疎通は取れたので、明日はハードを繋ぐだけ。事前にこちらを固めておいてほしい:

1. **本番前チェックの再確認**: `EditorDebugGoalSender` と `DebugTopCam` を**無効化 or 削除**する運用を忘れないこと（マウス誤爆・二重カメラ防止）。HMDでの操作は `SetGoal`（トリガー＋スティック）が担当。
2. **Quest Link の事前準備**: PC版 Meta Quest Link アプリのインストール確認（ペアリングは実機合流後）。
3. **XR設定の最終確認**: XR Plug-in Management → PC: Oculus にチェック、テレポートマーカーが見えない場合に備え Stereo Rendering Mode = Multi Pass を把握。
4. **ROS Settings は据え置き**: `192.168.3.247:10000 / ROS2`（研究室のネットワークが同じ前提。IPが変わる可能性があるなら、明日Ubuntu側で `ip a` を再確認して共有する）。
5. **initialpose の扱い**: フルデモ時は「実機TB3を地図原点(0,0,0)に物理的に置いてから Unity Play」。ずれたらRVizの 2D Pose Estimate で補正（Ubuntu側で対応）。

---

## 6. 明日 Phase 3 の段取り（研究室、TB3+HMD合流後）

Ubuntu側の T1–T4 はそのままで、**TB3の robot.launch を1本足すだけ**。

```bash
# [T0] TB3のRasPiにSSH（別途）
export TURTLEBOT3_MODEL=burger
ros2 launch turtlebot3_bringup robot.launch.py     # ← これで odom→base_footprint と /scan が出る
# 以降 T1(endpoint) / T3(nav2) / T4(pipeline) は今夜と同じ
```

検証は段階的に:
1. **RVizのみでNav2単体**: 2D Pose Estimate → 2D Goal Pose でTB3が動く（Unity抜きでnav2+実機の健全性確認）
2. **Unity(見下ろしクリック)→TB3が動く**（今夜のチェーンに実機TFが加わって完成）
3. **Quest Link → HMDでレイ/トリガー/スティック**
4. **フルデモ**（実機を原点に置いてPlay、initialpose自動送信）
5. 完成後 `EditorDebugGoalSender` / `DebugTopCam` 無効化

### チェックリスト（Phase 3）
- [ ] TB3 robot.launch → TFツリー map→odom→base_footprint が繋がる（`ros2 run tf2_ros tf2_echo map base_footprint`で確認）
- [ ] RVizでNav2単体動作
- [ ] Unityクリック送信でTB3移動
- [ ] Quest LinkでHMD動作
- [ ] フルデモ成功

---

## 7. まとめ

- **Phase 1（Unity送信側）+ Phase 2（Ubuntu受信側）+ 両者の実疎通 = 完了。**
- 残りは Phase 3（実機TB3 + HMD）のみ。ソフトの不具合や未実装はなし。
- 今夜の状態はいつでも再現可能（T1–T4のコマンドは上記）。

お疲れさまでした。明日は繋ぐだけです。
