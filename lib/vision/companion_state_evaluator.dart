import 'eye_state_detector.dart';
import 'head_offset_detector.dart';
import 'pose_state_detector.dart';
import 'posture_down_detector.dart';
import 'presence_detector.dart';
import 'vision_result.dart';

enum CompanionStatus {
  normal,
  attention,
  fatigue,
  distracted,
  postureDown,
  tooClose,
  userMissing,
}

extension CompanionStatusLabel on CompanionStatus {
  String get label {
    switch (this) {
      case CompanionStatus.normal:
        return '狀態：正常';
      case CompanionStatus.attention:
        return '注意：眨眼頻繁';
      case CompanionStatus.fatigue:
        return '疲勞警告：偵測到閉眼';
      case CompanionStatus.distracted:
        return '分心提醒：視線偏離';
      case CompanionStatus.postureDown:
        return '姿勢提醒：疑似趴下';
      case CompanionStatus.tooClose:
        return '坐姿警告：離螢幕太近';
      case CompanionStatus.userMissing:
        return '尚未偵測到完整使用者';
    }
  }
}

class CompanionAnalysis {
  const CompanionAnalysis({
    required this.visionResult,
    required this.eyeResult,
    required this.headOffsetResult,
    required this.postureDownResult,
    required this.poseResult,
    required this.presenceState,
    required this.status,
  });

  final VisionResult visionResult;
  final EyeDetectionResult eyeResult;
  final HeadOffsetDetectionResult headOffsetResult;
  final PostureDownDetectionResult postureDownResult;
  final PoseDetectionResult poseResult;
  final PresenceState presenceState;
  final CompanionStatus status;

  PoseState get poseState => poseResult.state;
}

class CompanionStateEvaluator {
  CompanionStateEvaluator({
    this.eyeStateDetector = const EyeStateDetector(),
    HeadOffsetDetector? headOffsetDetector,
    PostureDownDetector? postureDownDetector,
    this.poseStateDetector = const PoseStateDetector(),
    this.presenceDetector = const PresenceDetector(),
  })  : headOffsetDetector = headOffsetDetector ?? HeadOffsetDetector(),
        postureDownDetector = postureDownDetector ?? PostureDownDetector();

  final EyeStateDetector eyeStateDetector;
  final HeadOffsetDetector headOffsetDetector;
  final PostureDownDetector postureDownDetector;
  final PoseStateDetector poseStateDetector;
  final PresenceDetector presenceDetector;

  CompanionAnalysis evaluate({
    required VisionResult result,
    required int previousClosedFrameCount,
    required int previousDistractedFrameCount,
    required int previousPostureDownFrameCount,
    required bool shouldUpdatePostureDown,
  }) {
    final eyeResult = eyeStateDetector.evaluate(
      result: result,
      previousClosedFrameCount: previousClosedFrameCount,
    );
    final headOffsetResult = headOffsetDetector.evaluate(
      result: result,
      previousDistractedFrameCount: previousDistractedFrameCount,
    );
    final postureDownResult = postureDownDetector.evaluate(
      result: result,
      previousDownFrameCount: previousPostureDownFrameCount,
      shouldUpdate: shouldUpdatePostureDown,
    );
    final poseResult = poseStateDetector.evaluate(
      result: result,
      postureDownScore: postureDownResult.score,
      postureDownFrameCount: postureDownResult.downFrameCount,
      isPostureDown: postureDownResult.state == PostureDownState.down,
    );
    final presenceState = presenceDetector.evaluate(result);

    return CompanionAnalysis(
      visionResult: result,
      eyeResult: eyeResult,
      headOffsetResult: headOffsetResult,
      postureDownResult: postureDownResult,
      poseResult: poseResult,
      presenceState: presenceState,
      status: _combine(
        eyeState: eyeResult.state,
        headOffsetState: headOffsetResult.state,
        poseState: poseResult.state,
        presenceState: presenceState,
      ),
    );
  }

  CompanionStatus _combine({
    required EyeState eyeState,
    required HeadOffsetState headOffsetState,
    required PoseState poseState,
    required PresenceState presenceState,
  }) {
    if (eyeState == EyeState.fatigue) return CompanionStatus.fatigue;
    if (poseState == PoseState.postureDown) return CompanionStatus.postureDown;
    if (eyeState == EyeState.attention) return CompanionStatus.attention;
    if (headOffsetState == HeadOffsetState.distracted) {
      return CompanionStatus.distracted;
    }
    if (poseState == PoseState.tooClose) return CompanionStatus.tooClose;
    if (presenceState == PresenceState.away) return CompanionStatus.userMissing;
    return CompanionStatus.normal;
  }

  void reset() {
    headOffsetDetector.reset();
    postureDownDetector.reset();
  }
}
