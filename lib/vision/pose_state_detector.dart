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
    this.drowsyPitchThreshold = 26,
    this.drowsyHeadLowThreshold = 45,
    this.drowsyNoseDropThreshold = 28,
    this.readingProtectionHeadLowMax = 95,
    this.readingProtectionPostureScoreMax = 35,
    this.readingProtectionShoulderDropMax = 24,
    this.readingProtectionShoulderShrinkMax = 25,
    this.readingProtectionSideProneMax = 30,
    this.drowsyMaxShoulderDropScore = 50,
    this.drowsyMaxShoulderShrinkScore = 45,
  });

  final double drowsyPitchThreshold;
  final double drowsyHeadLowThreshold;
  final double drowsyNoseDropThreshold;
  final double readingProtectionHeadLowMax;
  final double readingProtectionPostureScoreMax;
  final double readingProtectionShoulderDropMax;
  final double readingProtectionShoulderShrinkMax;
  final double readingProtectionSideProneMax;
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
    final sideProneScore = postureDownResult.sideProneScore ?? 0;

    final stableReadingBody =
        postureDownResult.downFrameCount == 0 &&
        (postureDownResult.score ?? 0) < readingProtectionPostureScoreMax &&
        shoulderDropScore < readingProtectionShoulderDropMax &&
        shoulderShrinkScore < readingProtectionShoulderShrinkMax &&
        sideProneScore < readingProtectionSideProneMax;
    if (stableReadingBody && headLowScore < readingProtectionHeadLowMax) {
      return false;
    }

    final pitchSupportsHeadDrop =
        headPitch.abs() >= drowsyPitchThreshold &&
        (headLowScore >= 35 || noseDropScore >= 40);
    final geometrySupportsHeadDrop =
        headLowScore >= drowsyHeadLowThreshold &&
        noseDropScore >= drowsyNoseDropThreshold;
    final extremeHeadLowSupportsDrowsy =
        headLowScore >= readingProtectionHeadLowMax;

    return eyeState == EyeState.fatigue &&
        (pitchSupportsHeadDrop ||
            geometrySupportsHeadDrop ||
            extremeHeadLowSupportsDrowsy) &&
        shoulderDropScore < drowsyMaxShoulderDropScore &&
        shoulderShrinkScore < drowsyMaxShoulderShrinkScore;
  }
}
