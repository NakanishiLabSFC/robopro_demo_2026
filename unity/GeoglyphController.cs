#if UNITY_EDITOR
using UnityEngine;
using Unity.Robotics.ROSTCPConnector;
using Unity.Robotics.ROSTCPConnector.ROSGeometry;
using RosMessageTypes.Std;
using RosMessageTypes.Nav;

/// <summary>
/// 地上絵デモ 段階4（Windows/Unity側）。
/// - お題テキストを /draw_request(String) にPublish
/// - Ubuntuが生成した /geoglyph_path(nav_msgs/Path) を購読し LineRenderer でVR空間に描画
/// - 確認後 /execute_geoglyph(Bool=true) をPublishして nav2 巡回を開始させる
///
/// 前提:
///  - Robotics ▶ Generate ROS Messages で nav_msgs(Path) を生成しておくこと
///    （geometry_msgs は既存。std_msgs の String/Bool も生成済みか確認）
///  - ROS Settings: ROS IP=UbuntuのIP, Port=10000, Protocol=ROS2
///  - GameObjectに LineRenderer を付け、このスクリプトの lineRenderer に割当
///  - Ubuntu側: run_geoglyph.sh(generator) + waypoint_sender(auto_execute:=false) + nav2 を起動
///
/// エディタ専用(#if UNITY_EDITOR)。まずはマウス/キーで疎通確認し、後でVR UIに繋ぐ。
/// 座標: Ubuntuは map フレーム(FLU/右手系)で送るので From<FLU>() で Unity 座標へ変換する。
/// </summary>
public class GeoglyphController : MonoBehaviour
{
    [Header("ROSトピック名（Ubuntu側と一致させる）")]
    [SerializeField] string drawRequestTopic = "/draw_request";
    [SerializeField] string geoglyphPathTopic = "/geoglyph_path";
    [SerializeField] string executeTopic = "/execute_geoglyph";

    [Header("描画")]
    [SerializeField] LineRenderer lineRenderer;   // 軌跡表示用
    [SerializeField] float lineHeight = 0.05f;    // 地面から少し浮かせて見やすく

    [Header("テスト用お題（Rキーで送信）")]
    [SerializeField] string requestText = "うずまき";

    ROSConnection ros;

    void Start()
    {
        ros = ROSConnection.GetOrCreateInstance();
        ros.RegisterPublisher<StringMsg>(drawRequestTopic);
        ros.RegisterPublisher<BoolMsg>(executeTopic);
        ros.Subscribe<PathMsg>(geoglyphPathTopic, OnPath);
        Debug.Log("[Geoglyph] R=お題送信 / Space=実行(巡回開始)");
    }

    void Update()
    {
        // R: お題を送る → Ubuntuが生成 → OnPathで軌跡が返る
        if (Input.GetKeyDown(KeyCode.R))
        {
            var msg = new StringMsg(requestText);
            ros.Publish(drawRequestTopic, msg);
            Debug.Log("[Geoglyph] draw_request 送信: " + requestText);
        }
        // Space: 実行トリガ → waypoint_sender が nav2 へ送り巡回開始
        if (Input.GetKeyDown(KeyCode.Space))
        {
            ros.Publish(executeTopic, new BoolMsg(true));
            Debug.Log("[Geoglyph] execute_geoglyph 送信（巡回開始）");
        }
    }

    // Ubuntuから軌跡(map座標)を受信 → Unity座標へ変換して LineRenderer に描画
    void OnPath(PathMsg path)
    {
        int n = path.poses.Length;
        Debug.Log("[Geoglyph] geoglyph_path 受信: " + n + " 点");
        if (lineRenderer == null || n == 0) return;

        lineRenderer.positionCount = n;
        for (int i = 0; i < n; i++)
        {
            var p = path.poses[i].pose.position;   // ROS(map, FLU) の位置
            // ROS点 -> Unity座標（右手FLU -> 左手Unity）
            Vector3 u = new PointMsg(p.x, p.y, p.z).From<FLU>();
            u.y = lineHeight;                      // 地面すれすれに表示
            lineRenderer.SetPosition(i, u);
        }
    }
}
#endif
