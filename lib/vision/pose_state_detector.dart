import 'eye_state_detector.dart';
import 'posture_down_detector.dart';
import 'vision_result.dart';

enum PoseState { noPose, normal, detected, drowsy, postureDown }

class PoseDetectionResult {
  const PoseDetectionResult({
    required this.state,
    required this.postureDownScore,
    required this.postureDownFrameCount,
  });

  final PoseState state;
  final double? postureDownScore;
  final int postureDownFrameCount;
}

class PoseStateDetector {
  const PoseStateDetector({
    this.drowsyPitchThreshold = 32,
    this.drowsyHeadLowThreshold = 55,
    this.drowsyNoseDropThreshold = 70,
    this.drowsyMaxShoulderDropScore = 50,
    this.drowsyMaxShoulderShrinkScore = 45,
  });

  final double drowsyPitchThreshold;
  final double drowsyHeadLowThreshold;
  final double drowsyNoseDropThreshold;
  final double drowsyMaxShoulderDropScore;
  final double drowsyMaxShoulderShrinkScore;

  PoseDetectionResult evaluate({
    required VisionResult result,
    required PostureDownDetectionResult postureDownResult,
    required int postureDownFrameCount,
    required bool isPostureDown,
    required EyeState eyeState,
  }) {
    final postureDownScore = postureDownResult.score;
    final shoulderWidth = result.shoulderWidth;
    if (!result.hasPose || shoulderWidth == null) {
      if (isPostureDown) {
        return PoseDetectionResult(
          state: PoseState.postureDown,
          postureDownScore: postureDownScore,
          postureDownFrameCount: postureDownFrameCount,
        );
      }

      return PoseDetectionResult(
        state: PoseState.noPose,
        postureDownScore: postureDownScore,
        postureDownFrameCount: postureDownFrameCount,
      );
    }

    if (isPostureDown) {
      return PoseDetectionResult(
        state: PoseState.postureDown,
        postureDownScore: postureDownScore,
        postureDownFrameCount: postureDownFrameCount,
      );
    }

    final isDrowsy = _isDrowsyHeadDrop(
      result: result,
      postureDownResult: postureDownResult,
      eyeState: eyeState,
    );
    if (isDrowsy) {
      return PoseDetectionResult(
        state: PoseState.drowsy,
        postureDownScore: postureDownScore,
        postureDownFrameCount: postureDownFrameCount,
      );
    }

    return PoseDetectionResult(
      state: PoseState.normal,
      postureDownScore: postureDownScore,
      postureDownFrameCount: postureDownFrameCount,
    );
  }

  bool _isDrowsyHeadDrop({
    required VisionResult result,
    required PostureDownDetectionResult postureDownResult,
    required EyeState eyeState,
  }) {
    final headPitch = result.headPitch;
    if (!result.hasFace || headPitch == null) return false;

    final headLowScore = postureDownResult.headLowScore ?? 0;
    final noseDropScore = postureDownResult.noseDropScore ?? 0;
    final shoulderDropScore = postureDownResult.shoulderDropScore ?? 0;
    final shoulderShrinkScore = postureDownResult.shoulderShrinkScore ?? 0;

    return eyeState == EyeState.fatigue &&
        headPitch >= drowsyPitchThreshold &&
        headLowScore >= drowsyHeadLowThreshold &&
        noseDropScore >= drowsyNoseDropThreshold &&
        shoulderDropScore < drowsyMaxShoulderDropScore &&
        shoulderShrinkScore < drowsyMaxShoulderShrinkScore;
  }
}
