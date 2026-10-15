#!/bin/bash
# 地上絵ジェネレータ起動（段階1+2: テキスト -> 軌跡 -> /geoglyph_path）
# Claude API を使うなら事前に: export ANTHROPIC_API_KEY=sk-ant-...
# キー未設定なら自動でMOCK（オフライン検証）に切替。
source /opt/ros/humble/setup.bash
source ~/vr_demo_ws/install/setup.bash
# APIキーファイルがあれば読み込む（未編集のプレースホルダは無視）
if [ -f ~/vr_demo_ws/api_key.env ]; then
  source ~/vr_demo_ws/api_key.env
  [ "$ANTHROPIC_API_KEY" = "ここに貼る" ] && unset ANTHROPIC_API_KEY
fi
echo "[geoglyph] APIキー: $([ -n "$ANTHROPIC_API_KEY" ] && echo 'あり(Claudeモード)' || echo 'なし(MOCKモード)')"
echo "[geoglyph] 使い方: 別ターミナルで"
echo "  ros2 topic pub --once /draw_request std_msgs/msg/String \"{data: 'うずまき'}\""
echo "  ros2 topic echo /geoglyph_path nav_msgs/msg/Path   # 軌跡確認"
echo "  RViz2 で Fixed Frame=map, Path表示=/geoglyph_path を追加すると可視化できる"
ros2 run geoglyph geoglyph_generator
