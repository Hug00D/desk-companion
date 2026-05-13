import 'eye_state_detector.dart';
import 'pose_state_detector.dart';
import 'presence_detector.dart';
import 'vision_result.dart';

enum CompanionStatus { normal, attention, fatigue, tooClose, userMissing }

extension CompanionStatusLabel on CompanionStatus {
  String get label {
    switch (this) {
      case CompanionStatus.normal:
        return '狀態：正常';
      case CompanionStatus.attention:
        return '注意：眨眼頻繁';
      case CompanionStatus.fatigue:
        return '疲勞警告：偵測到閉眼';
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
    required this.poseState,
    required this.presenceState,
    required this.status,
  });

  final VisionResult visionResult;
  final EyeDetectionResult eyeResult;
  final PoseState poseState;
  final PresenceState presenceState;
  final CompanionStatus status;
}

class CompanionStateEvaluator {
  const CompanionStateEvaluator({
    this.eyeStateDetector = const EyeStateDetector(),
    this.poseStateDetector = const PoseStateDetector(),
    this.presenceDetector = const PresenceDetector(),
  });

  final EyeStateDetector eyeStateDetector;
  final PoseStateDetector poseStateDetector;
  final PresenceDetector presenceDetector;

  CompanionAnalysis evaluate({
    required VisionResult result,
    required int previousClosedFrameCount,
  }) {
    final eyeResult = eyeStateDetector.evaluate(
      result: result,
      previousClosedFrameCount: previousClosedFrameCount,
    );
    final poseState = poseStateDetector.evaluate(result);
    final presenceState = presenceDetector.evaluate(result);

    return CompanionAnalysis(
      visionResult: result,
      eyeResult: eyeResult,
      poseState: poseState,
      presenceState: presenceState,
      status: _combine(
        eyeState: eyeResult.state,
        poseState: poseState,
        presenceState: presenceState,
      ),
    );
  }

  CompanionStatus _combine({
    required EyeState eyeState,
    required PoseState poseState,
    required PresenceState presenceState,
  }) {
    if (eyeState == EyeState.fatigue) return CompanionStatus.fatigue;
    if (eyeState == EyeState.attention) return CompanionStatus.attention;
    if (poseState == PoseState.tooClose) return CompanionStatus.tooClose;
    if (presenceState == PresenceState.away) return CompanionStatus.userMissing;
    return CompanionStatus.normal;
  }
}
