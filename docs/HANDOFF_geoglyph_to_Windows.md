# 引き継ぎ書 — 地上絵デモ拡張（Ubuntu → Windows）／段階4以降

作成: 2026-07-07 / 作成者: Ubuntu側 Claude Code
対象読者: Windows側 Claude Code と Hyu
関連: 設計思想は `DESIGN_geoglyph_extension.md`、既存VRデモは `HANDOFF_reply_to_Windows.md`

---

## 0. 結論（TL;DR）

**Ubuntu(ROS2)側の地上絵拡張は、実キー含めて完動**した。残りは **Windows/Unity側の段階4** と **実機TB3での実巡回(Phase3)** のみ。

段階4のUnityスクリプト **`GeoglyphController.cs`** は**Ubuntu側で先に書いて同梱**した。Unityに入れて配線すれば疎通できる状態。

```
"うずまき" → Claude API(claude-opus-4-8, 構造化出力) → map座標変換 → /geoglyph_path(Path)
          → waypoint_sender → nav2 FollowWaypoints → 巡回   ← ここまで Ubuntu 完成
                    ↑ Unity(段階4)が /geoglyph_path を購読して VR表示、/execute_geoglyph で実行トリガ
```

---

## 1. Ubuntu側で完成・検証済みのこと（あなたは触らなくてよい）

`~/vr_demo_ws/src/geoglyph` パッケージ（新規）:
| ノード | 役割 | 状態 |
|---|---|---|
| `geoglyph_generator` | `/draw_request`(String) → Claude API または MOCK → map座標変換 → `/geoglyph_path`(nav_msgs/Path, frame=map) | ✅ 実キー動作 |
| `waypoint_sender` | `/geoglyph_path` 保持 → `/execute_geoglyph`(Bool) or auto_execute で nav2 `/follow_waypoints` へ送信 | ✅ 巡回検証 |

- Claude: `claude-opus-4-8`、**構造化出力(JSON Schema)** で `{"points":[{"x,y}]}` を強制。APIキーは **Ubuntu側 `~/vr_demo_ws/api_key.env`**(chmod600) に置く運用。Unityには渡さない。
- MOCK: キー無しでも 円/星/ハート/四角/うずまき を手続き生成（オフライン検証用）。
- 検証実績(実機なし): 「猫の顔」52点、「ヨット」14点をClaudeで生成→map範囲内→Path配信→FollowWaypoints受理→120点巡回(current_waypoint進行)。

### Ubuntu側の起動（あなたのテスト時、TB3無しでOK）
```bash
bash ~/vr_demo_ws/run_nav2.sh                 # nav2 + 地図
bash ~/vr_demo_ws/activate_nav2.sh            # ★ゴールが拒否される時のみ: nav2全ノードを手動active化
bash ~/vr_demo_ws/run_geoglyph.sh             # generator（api_key.envを自動読込→Claude/MOCK自動判定）
ros2 run geoglyph waypoint_sender --ros-args -p auto_execute:=false   # Unity実行トリガ待ちにする
```
**重要な注意**: nav2のautostartがCPU競合等で停滞し**全ノードがinactiveのまま**になることがある（症状=ゴール拒否／`ros2 lifecycle get /bt_navigator`がinactive）。その時は `activate_nav2.sh` を叩けば回復する。実機デモ時もこの保険を用意しておくこと。

---

## 2. 同梱ファイル: GeoglyphController.cs（段階4・Windows実装）

`GeoglyphController.cs` を持ち込んでいる。役割:
- `R`キー: お題テキストを `/draw_request`(String) にPublish → Ubuntuが生成
- 受信: `/geoglyph_path`(nav_msgs/Path) を購読し **LineRenderer** でVR空間に軌跡描画（map(FLU)→Unity座標へ `From<FLU>()` 変換）
- `Space`キー: `/execute_geoglyph`(Bool=true) をPublish → waypoint_senderがnav2へ送り巡回開始

### Windowsでの設置手順
1. **メッセージ生成**: `Robotics ▶ Generate ROS Messages` で **nav_msgs(Path)** を生成（geometry_msgsは既存。std_msgsの String/Bool も無ければ生成）。← これを忘れると `PathMsg`/`StringMsg`/`BoolMsg` が未定義でコンパイルエラー
2. `GeoglyphController.cs` を `Assets/Scripts/` に置く
3. 空GameObjectに **LineRenderer** コンポーネントを追加（幅0.05, マテリアルは任意の可視色）
4. 同GameObjectに `GeoglyphController` を追加し、Inspectorで:
   - `Line Renderer` = そのLineRenderer
   - トピック名は既定のまま(`/draw_request`,`/geoglyph_path`,`/execute_geoglyph`)
   - `Request Text` = テスト用お題（"うずまき" 等）
5. `Robotics ▶ ROS Settings`: ROS IP=UbuntuのIP(例 192.168.3.247), Port=10000, Protocol=ROS2

### 疎通テスト（HMD無し・実機無し）
1. Ubuntu側: run_nav2 → activate_nav2(必要時) → run_geoglyph → waypoint_sender(auto_execute:=false)
2. Unity Play → HUD接続確認
3. **R** → 数秒後(Claude生成)にGameビューへ軌跡がLine表示されれば **段階4疎通成功**
4. **Space** → Ubuntuの `waypoint_sender` ログに「FollowWaypoints へ N ウェイポイント送信/受理」が出れば実行トリガもOK（TB3無しなので実移動はしない＝正常）

### 注意
- `#if UNITY_EDITOR` 付き。まずキー操作で疎通確認し、後でVR UI（コントローラ/音声）に置き換える
- 座標整合: 軌跡は map フレーム基準。既存の地図表示(MapTransformer)と同じ平面に乗るはず。ずれる場合は MapTransformer の値と `lineHeight`/フレーム変換を確認
- APIキーはUnity側に一切不要（Ubuntuが持つ）

---

## 3. 役割分担（再掲・設計思想）

```
Windows(Unity) = 人が見る・操作する・可視化する層（APIキーを持たない）
Ubuntu(ROS2)   = AI生成・座標変換・ロボット制御層（APIキーを持つ）
```
この境界を越えない。Windowsは `/draw_request` を投げて `/geoglyph_path` を表示し `/execute_geoglyph` を送るだけ。生成AIも変換も巡回もUbuntu側。

---

## 4. 残タスク

### Windows(あなた)
- [ ] nav_msgs(Path) 等のメッセージ生成
- [ ] GeoglyphController.cs 設置・LineRenderer配線
- [ ] R/Space での疎通テスト（軌跡表示・実行トリガ）
- [ ] （発展）お題入力UI・軌跡の位置/回転/スケール編集（既存ControllerRayHit/SetGoalの操作系を流用）・進捗表示

### 統合/実機（Phase3, 研究室）
- [ ] 実機TB3で実際に各ウェイポイントを巡回して地上絵を描く
- [ ] 描画手段の決定（走行軌跡そのもの or ペン等の機構）※要相談

---

## 5. まとめ

- Ubuntu側は段階1-3＋実キーまで完動。`GeoglyphController.cs` も用意済み。
- Windowsはメッセージ生成→スクリプト設置→R/Spaceで疎通、が最短ルート。
- 既存VRデモ(単発goal)と同じendpoint/ネットワーク構成の上に乗る。地図・IP・ポートは既存デモと共通。

まずは段階4の疎通（R→軌跡表示）から。実機は最後。
