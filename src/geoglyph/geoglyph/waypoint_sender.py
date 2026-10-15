#!/usr/bin/env python3
"""
waypoint_sender — /geoglyph_path を nav2 の FollowWaypoints アクションへ送る橋渡しノード。

役割（設計書 DESIGN_geoglyph_extension.md の Ubuntu側 ③）:
  /geoglyph_path (nav_msgs/Path)         を購読・保持
  /execute_geoglyph (std_msgs/Bool=true) で保持中のPathを nav2 /follow_waypoints へ送信
    （auto_execute:=true なら Path 受信で即送信。Unity統合時は false にして実行トリガを待つ）

巡回制御本体は nav2_waypoint_follower（既存）が担う。このノードは変換と送信だけ。
"""
import rclpy
from rclpy.node import Node
from rclpy.action import ActionClient
from std_msgs.msg import Bool
from nav_msgs.msg import Path
from nav2_msgs.action import FollowWaypoints


class WaypointSender(Node):
    def __init__(self):
        super().__init__("waypoint_sender")
        self.declare_parameter("auto_execute", True)   # Path受信で即送信するか
        self.declare_parameter("action_name", "/follow_waypoints")
        # 表示用Path(密)を nav2 に送る前に間引く目標WP数。
        # Windows側知見: 密すぎると各WPのゴール許容誤差で絵がガタつき遅い→20前後推奨。0以下で間引き無効。
        self.declare_parameter("num_waypoints", 20)

        self.latest_path = None
        self._ac = ActionClient(self, FollowWaypoints,
                                self.get_parameter("action_name").value)
        self.create_subscription(Path, "/geoglyph_path", self.on_path, 10)
        self.create_subscription(Bool, "/execute_geoglyph", self.on_execute, 10)
        self.get_logger().info(
            "起動: auto_execute=%s / action=%s"
            % (self.get_parameter("auto_execute").value,
               self.get_parameter("action_name").value))

    def on_path(self, msg: Path):
        self.latest_path = msg
        self.get_logger().info("軌跡受信: %d 点" % len(msg.poses))
        if self.get_parameter("auto_execute").value:
            self.send()

    def on_execute(self, msg: Bool):
        if msg.data:
            self.send()

    def downsample(self, poses):
        """密な表示用点列 -> 粗いウェイポイント(先頭/末尾は必ず残す, インデックス等間隔)。"""
        num = int(self.get_parameter("num_waypoints").value)
        n = len(poses)
        if num <= 0 or n <= num:
            return list(poses)
        idxs = [round(i * (n - 1) / (num - 1)) for i in range(num)]
        # 重複除去(順序保持)
        seen, out = set(), []
        for i in idxs:
            if i not in seen:
                seen.add(i)
                out.append(poses[i])
        return out

    def send(self):
        if self.latest_path is None or not self.latest_path.poses:
            self.get_logger().warn("送信する軌跡がありません")
            return
        if not self._ac.wait_for_server(timeout_sec=5.0):
            self.get_logger().error(
                "FollowWaypoints アクションサーバに接続不可（nav2起動を確認）")
            return
        wps = self.downsample(self.latest_path.poses)
        goal = FollowWaypoints.Goal()
        goal.poses = wps
        self.get_logger().info(
            "FollowWaypoints へ %d ウェイポイント送信（表示用 %d 点を間引き）"
            % (len(goal.poses), len(self.latest_path.poses)))
        fut = self._ac.send_goal_async(goal, feedback_callback=self.on_feedback)
        fut.add_done_callback(self.on_goal_response)

    def on_goal_response(self, future):
        handle = future.result()
        if not handle.accepted:
            self.get_logger().warn("ゴールが拒否されました")
            return
        self.get_logger().info("ゴール受理。巡回開始")
        handle.get_result_async().add_done_callback(self.on_result)

    def on_feedback(self, fb):
        self.get_logger().info("巡回中: current_waypoint=%d"
                               % fb.feedback.current_waypoint)

    def on_result(self, future):
        res = future.result().result
        missed = list(res.missed_waypoints)
        self.get_logger().info("巡回完了。未達ウェイポイント: %s"
                               % (missed if missed else "なし"))


def main(args=None):
    rclpy.init(args=args)
    node = WaypointSender()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
