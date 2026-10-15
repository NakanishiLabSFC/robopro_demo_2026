# 設計書 — 地上絵デモ拡張（生成AI × VR × TB3）／2PC分担と設計思想

作成: 2026-07-07 / 作成者: Ubuntu側 Claude Code
対象読者: **Windows側 と Ubuntu側 の両Claude Code、および Hyu**
位置づけ: 既存「VRゴール送信デモ」(`HANDOFF_*.md`)の**発展構想**。実装前の設計合意用。

---

## 0. これは何か（TL;DR）

既存デモ「Questで指した1点にTB3が移動」を、
**「生成AI(Claude API)が地上絵の軌跡を生成 → TB3が地面を巡回して描く／VR空間に地上絵を表示」** に拡張する。

キーアイデア: **単発の goal_pose を、点列(ウェイポイント)の巡回に置き換える**。
nav2 には `nav2_waypoint_follower`（FollowWaypointsアクション）が最初から入っているので、巡回制御は自作不要。新規実装は「AIで軌跡を作る部分」と「軌跡をnav2に渡す部分」だけ。

```
[テキスト指示 "うずまきの地上絵"]
      ↓  Claude API (claude-opus-4-8, 構造化出力)
   軌跡の点列 [(x,y), ...] (正規化座標)
      ↓  map座標へスケール変換
   PoseStamped[] (ウェイポイント列)
      ↓  nav2 FollowWaypoints (/follow_waypoints)
   TB3が順に巡回 → 地面に軌跡（＝地上絵）
      ↕  Unity/Questで軌跡をVR表示・編集・確認
```

---

## 1. 設計思想（両PC共通の原則）

1. **既存資産を壊さず積む**: 今夜作った `vr_demo_ws`(nav2+endpoint+pipeline) と Unityプロジェクトをそのまま土台にする。地上絵は「pipelineを単発goalからFollowWaypointsに差し替える発展形」。
2. **APIキーはUbuntu側に置く**: Claude API呼び出しは**Ubuntuのノードに集約**。Unity(Windows)の配布ビルドに鍵を埋め込まない（漏洩防止）。UnityはあくまでUI/可視化。
3. **役割で切る**: Windows=「人が見る・操作する・可視化する」層、Ubuntu=「AI生成・座標変換・ロボット制御」層。この境界を越えない。
4. **構造化出力で堅牢に**: AIの軌跡は JSON Schema を強制(`{"points":[{"x":..,"y":..}]}`)。自由テキストをパースしない。
5. **実機なしで最大限進める**: AIの軌跡生成→RViz描画、Unityの軌跡表示、までは実機TB3なしで検証できる。実機は最後の「実際に描く」段階だけ。

---

## 2. 2PCの役割分担

```
┌──────────── Windows PC (Unity/Quest) ────────────┐
│ 層: 人とのインタフェース・可視化                 │
│ - テキスト/音声で「何を描くか」を入力するUI      │
│ - AIが返した軌跡をVR空間にライン表示(LineRenderer)│
│ - Questコントローラで軌跡の位置/向き/スケール調整 │
│ - 確認したら「実行」を送る                       │
│ ※ Claude APIキーは持たない。ROS経由でやりとり    │
└───────────────────┬──────────────────────────────┘
                    │ ROS-TCP-Endpoint (TCP:10000)
┌───────────────────┴──────────────────────────────┐
│ 層: AI生成・変換・ロボット制御 (Ubuntu ROS2)     │
│ - Claude APIクライアントノード(鍵はここ)         │
│ - 座標変換(正規化→map)                            │
│ - ウェイポイント送出→nav2 FollowWaypoints        │
│ - TB3実機制御                                     │
└───────────────────────────────────────────────────┘
```

### Windows側(Unity)がやること
| 項目 | 内容 |
|---|---|
| 入力UI | 「何を描くか」のテキスト入力(またはプリセット選択)。ROSトピック `/draw_request`(String)へPublish |
| 軌跡受信・表示 | Ubuntuから返る軌跡トピック `/geoglyph_path`(nav_msgs/Path 等)を購読し、`LineRenderer`でVR空間に描画 |
| 編集操作 | コントローラで軌跡全体の位置/回転/スケールを調整(既存のControllerRayHit/SetGoalの操作系を流用) |
| 実行トリガ | OKなら `/execute_geoglyph`(Bool or 確定Path)をPublish |
| 進捗表示 | nav2のフィードバック(残距離・現在ウェイポイント番号)を受けてVRに進捗表示 |

### Ubuntu側(ROS2)がやること
| 項目 | 内容 | 新規/既存 |
|---|---|---|
| ① Claude APIノード | `anthropic` SDK, `claude-opus-4-8`, 構造化出力で `/draw_request`(text)→軌跡JSON→`/geoglyph_path`(Path) を配信。**APIキー保持** | 新規 |
| ② 座標変換 | 正規化/画像座標→map物理座標(map.yamlのresolution/origin基準)。MapTransformerと同じ計算 | 新規(ロジック流用) |
| ③ ウェイポイント送出 | 確定Path→`PoseStamped[]`→nav2の`/follow_waypoints`アクションへ | 新規(薄い) |
| 巡回制御本体 | ウェイポイントを順に辿る | **nav2_waypoint_follower(既存)** ✅ |
| endpoint/nav2/実機 | 既存の`vr_demo_ws`土台 | 既存 ✅ |

**Ubuntu側の新規実装は実質①②③の3ノードだけ**(しかも②③は薄い)。巡回はnav2既存機能。

---

## 3. Claude API の設計メモ（Ubuntu側①ノード）

- モデル: **`claude-opus-4-8`**（最新・高能力）
- 呼び出し: 1回のLLM呼び出し(分類/生成タスク)。エージェント不要。
- **構造化出力**でスキーマ強制 → パース不要・壊れない:
  ```json
  {"type":"object",
   "properties":{"points":{"type":"array","items":{
     "type":"object",
     "properties":{"x":{"type":"number"},"y":{"type":"number"}},
     "required":["x","y"],"additionalProperties":false}}},
   "required":["points"],"additionalProperties":false}
  ```
- 座標系の約束: AIには「0〜1の正規化座標で点列を返す」と指示 → ②で地図サイズにスケール。
- 鍵の扱い: `ANTHROPIC_API_KEY` を**Ubuntuの環境変数**に置く。Unity側には一切渡さない。

---

## 4. 「エンドポイント複数」の判断基準

| やりたいこと | エンドポイント構成 |
|---|---|
| **1台のTB3で地上絵**（まずここ） | エンドポイント1個で十分。今の構成のまま |
| **複数台のTB3で分担して描く（群ロボット地上絵）** | ロボットごとに namespace + エンドポイント分離(ポート10000,10001… / `robot1/` `robot2/`)。※既存デモで見送ったnamespace付きnav2構成が、ここで本命になる |
| **複数のUnity/Questクライアント** | クライアントごとにエンドポイント分離 |

→ **最初のプロトタイプは1エンドポイント**で組み、群ロボット化する段階で複数化する。

---

## 5. 段階的な進め方（実機依存度が低い順）

1. **[Ubuntu単体]** ①Claude APIノード試作: `/draw_request` に文字列 → 軌跡JSON生成 → `ros2 topic echo /geoglyph_path` で点列確認（実機不要）
2. **[Ubuntu単体]** ②③で map座標に変換し、**RVizに軌跡を描画**して見た目確認（実機不要）
3. **[Ubuntu単体]** nav2 FollowWaypoints にダミー軌跡を流し、アクション受理まで確認（実機不要、今夜のloopbackと同じ要領）
4. **[Windows]** Unityで `/geoglyph_path` を購読し `LineRenderer` でVR表示、コントローラで編集
5. **[統合]** テキスト入力→AI生成→VR確認→実行→TB3が実際に巡回（実機合流後）

段階1〜3はUbuntu側だけで今すぐ着手可能。段階4はWindows側の担当。

---

## 6. 未確定・要相談ポイント

- 「地上絵を描く」の物理手段: TB3が走った軌跡そのものを絵とするのか、ペン/チョーク等の描画機構を積むのか（ハード検討）
- 軌跡の閉曲線/一筆書き制約: TB3は一筆書きが自然。AIに「一筆書きで」と制約を与えるか
- スケール/安全: 地図(教室)に収まるサイズにクリップ。障害物回避はnav2が担保
- 音声入力にするか（Quest側でSTT→text）

---

## 7. まとめ

- **境界**: Windows=UI/可視化、Ubuntu=AI生成/変換/ロボット制御。APIキーはUbuntu側。
- **新規実装**: Ubuntu 3ノード(①API ②変換 ③送出)＋Unity(軌跡表示・編集)。巡回はnav2既存。
- **土台**: 今夜の`vr_demo_ws`をそのまま使い、pipelineを単発goalからFollowWaypointsに発展。
- **着手**: 段階1(Claude APIノード試作)はUbuntu単体で今すぐ可能。

この設計で認識を合わせてから、まず段階1のプロトタイプを作るのが良い。
