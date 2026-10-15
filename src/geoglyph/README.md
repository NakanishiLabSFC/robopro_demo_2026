# geoglyph — 地上絵デモ拡張（Ubuntu側 段階1+2）

生成AI(Claude API)またはMOCKで地上絵の軌跡を生成し `nav_msgs/Path` として配信するROS2パッケージ。
設計は `~/Downloads/DESIGN_geoglyph_extension.md` を参照。

## ノード
- `geoglyph_generator`
  - 購読: `/draw_request` (std_msgs/String) … 何を描くか（例: "うずまき", "円 circle", "star", "ハート", "四角"）
  - 配信: `/geoglyph_path` (nav_msgs/Path, frame_id="map") … map座標に変換済みのウェイポイント列
  - `ANTHROPIC_API_KEY` があれば Claude API (claude-opus-4-8, 構造化出力)。無ければ自動でMOCK(手続き生成)。

## 使い方
```bash
# 起動（MOCK or Claude 自動判定）
bash ~/vr_demo_ws/run_geoglyph.sh
# 別ターミナル
ros2 topic pub --once /draw_request std_msgs/msg/String "{data: 'うずまき'}"
ros2 topic echo /geoglyph_path nav_msgs/msg/Path
```

## パラメータ（map差し替え時に更新）
resolution(0.05) / origin_x(-2.15) / origin_y(-3.25) / width_px(114) / height_px(141)
/ inset(0.15 端余白) / max_points(200) / model(claude-opus-4-8) / use_mock(false)

## 検証済み(2026-07-07, 実機なし)
MOCKで 円/星/ハート/四角/うずまき を生成・配信。座標が地図範囲(x:-2.15..3.55, y:-3.25..3.8)内に収まることを確認。

## 段階3（実装済 2026-07-07）: waypoint_sender ノード
- 購読: `/geoglyph_path` (Path) を保持 / `/execute_geoglyph` (Bool=true) で送信トリガ
- 送信: nav2 `/follow_waypoints` (FollowWaypoints) へウェイポイント列を送る
- パラメータ: auto_execute(true=Path受信で即送信, Unity統合時はfalse) / action_name(/follow_waypoints)
- 検証済: generator→sender→FollowWaypoints受理→巡回(current_waypoint進行)まで確認(実機なし)

- 間引き: waypoint_sender は表示用の密なPath(120点)を nav2 へ送る前に num_waypoints(既定20)に間引く。
  （Windows知見: 密すぎると各WPのゴール許容誤差で絵がガタつき遅い→20前後推奨）

### フルチェーン起動（実機なしテスト）
```bash
bash ~/vr_demo_ws/fake_tf.sh &             # ★TB3無しの時だけ: 静的TFでcostmapを通しnav2フル起動
bash ~/vr_demo_ws/run_nav2.sh              # nav2+地図
ros2 run geoglyph geoglyph_generator       # 生成
ros2 run geoglyph waypoint_sender --ros-args -p auto_execute:=false -p num_waypoints:=20
ros2 topic pub --once /draw_request std_msgs/msg/String "{data: 'うずまき'}"  # お題
ros2 topic pub --once /execute_geoglyph std_msgs/msg/Bool "{data: true}"      # 実行(巡回)
```
※【重要】TB3が無いと controller_server の costmap が odom→base_footprint TF を待って
activateでブロックし、nav2全体が上がらない（ゴール拒否の正体）。→ `fake_tf.sh` で静的TFを出せば
フル起動しFollowWaypoints受理＆経路計画まで確認できる。**実機TB3を使う時は fake_tf.sh を起動しない**
（本物のodom/TFと競合）。activate_nav2.sh は waypoint_follower単体を無理やり上げる応急策で、
本筋は fake_tf。

## 次の段階（未実装）
- 段階4: Unity(Windows)で `/geoglyph_path` を LineRenderer 表示・編集、`/execute_geoglyph` で実行
- Claudeモードの実キー疎通テスト（要 ANTHROPIC_API_KEY）
- 実機TB3で実際に巡回描画（Phase3合流後）
