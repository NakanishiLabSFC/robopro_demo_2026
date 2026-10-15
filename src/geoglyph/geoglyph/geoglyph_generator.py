#!/usr/bin/env python3
"""
geoglyph_generator — テキスト指示から地上絵の軌跡を生成し nav_msgs/Path として配信するノード。

役割（設計書 DESIGN_geoglyph_extension.md の Ubuntu側 ①+②）:
  /draw_request (std_msgs/String)  を購読
    -> Claude API (claude-opus-4-8, 構造化出力) または MOCK で 0..1 正規化点列を生成
    -> map 座標へスケール変換（map.yaml の resolution/origin 基準）
    -> /geoglyph_path (nav_msgs/Path, frame_id="map") を配信

APIキー(ANTHROPIC_API_KEY)が無い/anthropic未導入なら自動で MOCK に切替（オフライン検証可）。
MOCKは指示文のキーワード(spiral/circle/star/heart/square/渦/円/星/ハート/四角)で図形を選ぶ。
"""
import os
import json
import math

import rclpy
from rclpy.node import Node
from std_msgs.msg import String
from nav_msgs.msg import Path
from geometry_msgs.msg import PoseStamped

# Claude API へ返させる軌跡のJSON Schema（構造化出力で強制 -> パース不要で堅牢）
POINTS_SCHEMA = {
    "type": "object",
    "properties": {
        "points": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "x": {"type": "number"},
                    "y": {"type": "number"},
                },
                "required": ["x", "y"],
                "additionalProperties": False,
            },
        }
    },
    "required": ["points"],
    "additionalProperties": False,
}


class GeoglyphGenerator(Node):
    def __init__(self):
        super().__init__("geoglyph_generator")

        # --- パラメータ（map.yaml の既定値。地図差し替え時はここを更新） ---
        self.declare_parameter("resolution", 0.05)
        self.declare_parameter("origin_x", -2.15)
        self.declare_parameter("origin_y", -3.25)
        self.declare_parameter("width_px", 114)
        self.declare_parameter("height_px", 141)
        self.declare_parameter("inset", 0.15)          # 地図端からの余白(割合)
        self.declare_parameter("max_points", 200)
        self.declare_parameter("target_points", 100)   # Claudeに要求する目安点数（密度）
        self.declare_parameter("model", "claude-opus-4-8")
        self.declare_parameter("use_mock", False)      # True で強制MOCK

        self.pub = self.create_publisher(Path, "/geoglyph_path", 10)
        self.sub = self.create_subscription(String, "/draw_request", self.on_request, 10)

        # Claude 利用可否を判定（キー & SDK があるか）
        self.client = None
        forced_mock = self.get_parameter("use_mock").value
        if not forced_mock and os.environ.get("ANTHROPIC_API_KEY"):
            try:
                import anthropic
                self.client = anthropic.Anthropic()
                self.get_logger().info("Claude API モードで起動 (model=%s)"
                                        % self.get_parameter("model").value)
            except Exception as e:
                self.get_logger().warn("anthropic 初期化失敗、MOCKに切替: %r" % e)
        if self.client is None:
            self.get_logger().info("MOCK モードで起動（APIキー未設定 or use_mock=true）")

        self.get_logger().info('待機中: `ros2 topic pub /draw_request std_msgs/String "{data: \'うずまき\'}"`')

    # ---- リクエスト受信 ----
    def on_request(self, msg: String):
        text = (msg.data or "").strip()
        self.get_logger().info("draw_request: %r" % text)
        try:
            pts = self.generate_points(text)
        except Exception as e:
            self.get_logger().error("軌跡生成失敗: %r" % e)
            return
        if not pts:
            self.get_logger().warn("点列が空でした")
            return
        path = self.to_map_path(pts)
        self.pub.publish(path)
        self.get_logger().info("配信: /geoglyph_path (%d点)" % len(path.poses))

    # ---- 0..1 正規化点列を生成（Claude or MOCK） ----
    def generate_points(self, text: str):
        if self.client is not None:
            return self.generate_with_claude(text)
        return self.generate_mock(text)

    def generate_with_claude(self, text: str):
        model = self.get_parameter("model").value
        maxp = int(self.get_parameter("max_points").value)
        tgt = int(self.get_parameter("target_points").value)
        lo = max(30, int(tgt * 0.7))
        prompt = (
            "あなたは一筆書きの地上絵デザイナーです。次のお題を、1台の移動ロボットが"
            "順に辿って描ける一筆書きの軌跡にしてください。座標は 0.0〜1.0 に正規化する。\n"
            f"■点数: 形がはっきり分かるよう **{lo}〜{tgt}点程度の十分密な点列** にする"
            f"（最大 {maxp} 点まで可）。カクカクさせない。\n"
            "■曲線部は細かく等間隔にサンプリングし、角のある形は頂点を確実に含める。\n"
            "■隣り合う点は近距離で滑らかに繋がる順序にし、始点から終点まで一筆書きにする。\n"
            "■お題の輪郭が読み取れることを最優先。キャンバス(0..1)の8割程度を使って大きく描く。\n"
            f"お題: {text}"
        )
        resp = self.client.messages.create(
            model=model,
            max_tokens=16000,
            messages=[{"role": "user", "content": prompt}],
            output_config={"format": {"type": "json_schema", "schema": POINTS_SCHEMA}},
        )
        if resp.stop_reason == "refusal":
            raise RuntimeError("Claudeが安全上の理由で拒否しました")
        txt = next(b.text for b in resp.content if b.type == "text")
        data = json.loads(txt)
        return [(float(p["x"]), float(p["y"])) for p in data["points"]]

    def generate_mock(self, text: str):
        maxp = int(self.get_parameter("max_points").value)
        t = text.lower()
        def has(*ks):
            return any(k in text or k in t for k in ks)

        n = min(maxp, 120)
        pts = []
        if has("circle", "円", "まる"):
            for i in range(n):
                a = 2 * math.pi * i / (n - 1)
                pts.append((0.5 + 0.4 * math.cos(a), 0.5 + 0.4 * math.sin(a)))
        elif has("star", "星", "ほし"):
            k = 5
            for i in range(k * 2 + 1):
                a = math.pi / 2 + math.pi * i / k
                r = 0.45 if i % 2 == 0 else 0.18
                pts.append((0.5 + r * math.cos(a), 0.5 + r * math.sin(a)))
        elif has("heart", "ハート"):
            for i in range(n):
                tt = math.pi * (2 * i / (n - 1) - 1)
                x = 16 * math.sin(tt) ** 3
                y = 13 * math.cos(tt) - 5 * math.cos(2*tt) - 2 * math.cos(3*tt) - math.cos(4*tt)
                pts.append((0.5 + x / 40.0, 0.5 + y / 40.0))
        elif has("square", "四角", "しかく"):
            corners = [(0.15, 0.15), (0.85, 0.15), (0.85, 0.85), (0.15, 0.85), (0.15, 0.15)]
            per = max(2, n // 4)
            for i in range(len(corners) - 1):
                x0, y0 = corners[i]; x1, y1 = corners[i + 1]
                for j in range(per):
                    s = j / per
                    pts.append((x0 + (x1 - x0) * s, y0 + (y1 - y0) * s))
            pts.append(corners[-1])
        else:  # 既定: うずまき(spiral)
            turns = 3.0
            for i in range(n):
                s = i / (n - 1)
                a = 2 * math.pi * turns * s
                r = 0.45 * s
                pts.append((0.5 + r * math.cos(a), 0.5 + r * math.sin(a)))
        return pts

    # ---- 0..1 -> map座標 -> Path ----
    def to_map_path(self, pts):
        res = self.get_parameter("resolution").value
        ox = self.get_parameter("origin_x").value
        oy = self.get_parameter("origin_y").value
        wpx = self.get_parameter("width_px").value
        hpx = self.get_parameter("height_px").value
        inset = self.get_parameter("inset").value

        w_m = wpx * res
        h_m = hpx * res
        x0 = ox + inset * w_m
        y0 = oy + inset * h_m
        span_x = (1.0 - 2 * inset) * w_m
        span_y = (1.0 - 2 * inset) * h_m

        world = [(x0 + nx * span_x, y0 + ny * span_y) for (nx, ny) in pts]

        path = Path()
        path.header.frame_id = "map"
        path.header.stamp = self.get_clock().now().to_msg()
        for i, (wx, wy) in enumerate(world):
            ps = PoseStamped()
            ps.header.frame_id = "map"
            ps.header.stamp = path.header.stamp
            ps.pose.position.x = float(wx)
            ps.pose.position.y = float(wy)
            # 進行方向を向く四元数（次点への heading）
            nx_, ny_ = world[min(i + 1, len(world) - 1)]
            yaw = math.atan2(ny_ - wy, nx_ - wx)
            ps.pose.orientation.z = math.sin(yaw / 2.0)
            ps.pose.orientation.w = math.cos(yaw / 2.0)
            path.poses.append(ps)
        return path


def main(args=None):
    rclpy.init(args=args)
    node = GeoglyphGenerator()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
