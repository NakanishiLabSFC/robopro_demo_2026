#if UNITY_EDITOR
using UnityEngine;
using Unity.Robotics.ROSTCPConnector;
using RosMessageTypes.Geometry;
using Unity.Robotics.ROSTCPConnector.ROSGeometry;

/// <summary>
/// HMD無しでゴール送信を検証するためのデバッグ用スクリプト（エディタ専用）。
/// マウス左クリック → メインカメラからレイ → 床レイヤーとの衝突点をゴールとして送信する。
/// SetGoal.cs と同じ FLU 変換・同じトピック・同じ PoseStamped でPublishするため、
/// 既存スクリプト（SetGoal / GoalPublisher）には一切手を加えず自己完結で動作する。
/// 本番シーンでは無効化（コンポーネントのチェックを外す）しておき、疎通テスト時のみONにする。
/// </summary>
public class EditorDebugGoalSender : MonoBehaviour
{
    [Header("GoalPublisher の goalTopicName と一致させること")]
    [SerializeField] string goalTopicName = "goal_pose_unity";
    [Header("レイの設定")]
    [SerializeField] Camera rayCamera;               // 未指定なら Camera.main を使用
    [SerializeField] LayerMask collisionLayer;       // 床のレイヤー（ControllerRayHit と同じ）
    [SerializeField] float maxDistance = 100f;
    [Header("送信するゴールの向き（Unity Y軸まわりの角度）")]
    [SerializeField] float goalYawDegrees = 0f;

    ROSConnection ros;

    void Start()
    {
        ros = ROSConnection.GetOrCreateInstance();
        // GoalPublisher が同トピックを登録済みでも再登録は無害
        ros.RegisterPublisher<PoseStampedMsg>(goalTopicName);
        if (rayCamera == null) rayCamera = Camera.main;
        Debug.Log("[EditorDebugGoalSender] 有効。Gameビューを左クリックでゴール送信します。");
    }

    void Update()
    {
        if (!Input.GetMouseButtonDown(0)) return;
        if (rayCamera == null) { Debug.LogWarning("[EditorDebugGoalSender] カメラ未設定"); return; }

        Ray ray = rayCamera.ScreenPointToRay(Input.mousePosition);
        if (!Physics.Raycast(ray, out RaycastHit hit, maxDistance, collisionLayer))
        {
            Debug.Log("[EditorDebugGoalSender] 床にヒットせず（collisionLayer / 床コライダーを確認）");
            return;
        }
        SendGoal(hit.point, Quaternion.Euler(0f, goalYawDegrees, 0f));
    }

    // SetGoal.CreateGoalPoseMsg と同じ変換ロジックで PoseStamped を作り送信する
    void SendGoal(Vector3 unityPosition, Quaternion unityRotation)
    {
        Vector3<FLU> rosPosition = unityPosition.To<FLU>();
        Quaternion<FLU> rosRotation = unityRotation.To<FLU>();

        PoseStampedMsg msg = new PoseStampedMsg();
        msg.header.stamp.sec = 0;
        msg.header.stamp.nanosec = 0;
        msg.header.frame_id = "map";
        msg.pose.position.x = rosPosition.x;
        msg.pose.position.y = rosPosition.y;
        msg.pose.position.z = rosPosition.z;
        msg.pose.orientation.x = rosRotation.x;
        msg.pose.orientation.y = rosRotation.y;
        msg.pose.orientation.z = rosRotation.z;
        msg.pose.orientation.w = rosRotation.w;

        ros.Publish(goalTopicName, msg);
        Debug.Log($"[EditorDebugGoalSender] Goal送信 ({goalTopicName}): " +
                  $"x={rosPosition.x:F3}, y={rosPosition.y:F3}, yaw={goalYawDegrees}deg");
    }
}
#endif
