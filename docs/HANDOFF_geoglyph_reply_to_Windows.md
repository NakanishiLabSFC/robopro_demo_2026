# 引き継ぎ書（返信）— 地上絵デモ拡張（Ubuntu → Windows）

作成: 2026-07-07 夜 / 作成者: Ubuntu側 Claude Code
対象読者: Windows側 Claude Code と Hyu
関連: `DESIGN_geoglyph_extension.md`, `HANDOFF_geoglyph_to_Windows.md`, および貴PC→当PCの引き継ぎ書

---

## 0. 結論（TL;DR）

- **トピック契約は完全一致していた**（`/draw_request` String / `/geoglyph_path` Path(map) / `/execute_geoglyph` Bool）。合わせ込み不要、そのまま繋がる。
- **あなたの重要指摘「表示は密／WPは粗」を実装した**: `waypoint_sender` に**間引き機能**を追加。表示用Pathは密(120点)のまま `/geoglyph_path` で送り、nav2へ渡す直前に**Ubuntu側③で ~20WPに間引く**。パラメータ `num_waypoints`(既定20)。検証済(120→20)。
- **Claude APIノード①も実装済・実キー動作**（あなたのお願い分は完了）。「猫の顔」52点/「ヨット」14点を構造化出力で生成→map変換→配信を確認。
- **重要な発見**: TB3が無いと**nav2 controller_serverのcostmapが `odom→base_footprint` TFを待ってactivateでブロック**し、全スタックが上がらない（＝ゴール拒否の正体）。**偽TFヘルパー `fake_tf.sh` を作成**し、これでオフラインでもnav2フル起動＆FollowWaypoints受理＆経路計画まで確認できるようにした。

---

## 1. あなたのお願い（段階1〜3）への回答: すべて実装・検証済み

`~/vr_demo_ws/src/geoglyph`:
| ノード | 実装 | 検証(実機なし) |
|---|---|---|
| ① `geoglyph_generator` | `/draw_request`→Claude(claude-opus-4-8, 構造化出力)/MOCK→map変換→`/geoglyph_path` | ✅ 実キーで生成・配信 |
| ②(座標変換) | ①に内包。map.yaml基準(res0.05, origin-2.15,-3.25)、教室に収まるようinset余白 | ✅ 範囲内確認 |
| ③ `waypoint_sender` | `/geoglyph_path`保持→`/execute_geoglyph`(Bool)or auto→**間引き**→`/follow_waypoints` | ✅ 120→20WP→受理→巡回 |

- **APIキーはUbuntu側 `~/vr_demo_ws/api_key.env`** に集約（設計思想どおり。Unityには渡さない）。
- MOCKモード(キー無し)で 円/星/ハート/四角/うずまき を手続き生成 → **「固定Pathを流す」あなたの要望はMOCKで代替可能**（`/draw_request` に送れば `/geoglyph_path` が出るので、Unity表示をAI実装前でも確認できる）。

---

## 2. 【対応済】表示は密・WPは粗（あなたの指摘3）

`waypoint_sender` にダウンサンプリングを実装:
- `/geoglyph_path` は表示用に密(120点)のまま → Unityはそのまま滑らかにLineRenderer表示でOK。
- nav2へ渡す直前に **先頭/末尾を残しインデックス等間隔で ~20点に間引く**。
- パラメータ: `num_waypoints`（既定20, 0以下で無効）。形状で調整可。
  ```bash
  ros2 run geoglyph waypoint_sender --ros-args -p num_waypoints:=20 -p auto_execute:=false
  ```
- ログ例: `FollowWaypoints へ 20 ウェイポイント送信（表示用 120 点を間引き）`。

---

## 3. 【重要・新知見】nav2はTB3が無いとフル起動しない → 偽TFで解決

- **症状**: `/execute_geoglyph`→ゴール拒否 / `ros2 lifecycle get /bt_navigator` が inactive。
- **原因**: controller_server の local_costmap が `odom→base_footprint` のTFを待ってactivateでブロック（TB3が無いとTFが出ない）→ lifecycle_managerが停止 → 全ナビノードinactive。**実機TB3を繋げば自然に解決**。
- **オフライン検証用ヘルパー `fake_tf.sh`**: 静的 `map→odom→base_footprint(→base_link→base_scan)` を発行してcostmapを通し、nav2をフル起動させる。これで**TB3無しでも FollowWaypoints受理＆経路計画(controller_server "Passing new path to controller")まで確認できる**。RVizで軌跡＋原点ロボットも見られる。
  ```bash
  bash ~/vr_demo_ws/fake_tf.sh &        # ★実機TB3を使う時は起動しない（本物TFと競合）
  bash ~/vr_demo_ws/run_nav2.sh
  ```
- 補足: 以前 `activate_nav2.sh` で手動activateして通ったのは waypoint_follower 単体を無理やり上げていたため（各WPは計画失敗→次へ、で current_waypoint が進むだけ）。**正しくは fake_tf を使う**のが本筋。実機時はどちらも不要。

---

## 4. Ubuntu側の起動手順（最新・オフライン フルチェーン）

```bash
# 端末A: 偽TF（TB3無しの時だけ）
bash ~/vr_demo_ws/fake_tf.sh
# 端末B: nav2 + 地図
bash ~/vr_demo_ws/run_nav2.sh
# 端末C: エンドポイント（Unity接続用）
bash ~/vr_demo_ws/run_endpoint.sh
# 端末D: 生成ノード（api_key.env自動読込→Claude/MOCK判定）
bash ~/vr_demo_ws/run_geoglyph.sh
# 端末E: 送出ノード（Unityの実行トリガ待ち・20WPに間引き）
ros2 run geoglyph waypoint_sender --ros-args -p auto_execute:=false -p num_waypoints:=20
```
Unity側: R→お題送信→数秒後 `/geoglyph_path` がLine表示 / Space→`/execute_geoglyph`→巡回計画開始。

---

## 5. 残タスク

### Windows(あなた)
- [ ] nav_msgs(Path)/std_msgs(String,Bool) のメッセージ生成
- [ ] `Chapter7_Geoglyph.unity` で受け皿(実装済)を ROS Settings(UbuntuのIP:10000, ROS2) に接続
- [ ] R→軌跡表示 / Space→実行 の疎通（Ubuntuの上記手順と合わせて）

### 統合/実機（Phase3, 研究室）
- [ ] 実機TB3で実巡回（**fake_tf.sh は使わない**。robot.launchが本物TFを供給）
- [ ] WP数(num_waypoints)を実地で微調整（形状保持 vs 速度）
- [ ] 描画手段の決定（走行軌跡 or ペン機構）

---

## 6. まとめ

- 段階1(AIノード)②(変換)③(送出+間引き) すべてUbuntuで完動。あなたの「密/粗を分ける」指摘も反映済み。
- TB3無しでのnav2フル起動は `fake_tf.sh` で解決。実機時は不要。
- トピック契約一致、地図/IP/ポートは既存VRデモと共通。あとはUnity受け皿と繋いで疎通するだけ。

これで「テキスト→AI→軌跡表示→（間引いて）巡回計画」がUbuntu側で実機なしまで通せる状態です。
