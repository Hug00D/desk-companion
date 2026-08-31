import 'dart:math' as math;

enum RawFrameState {
  normal('normal'),
  eyeClosed('eye_closed'),
  headTurned('head_turned'),
  postureDown('posture_down'),
  userMissing('user_missing');

  const RawFrameState(this.csvValue);

  final String csvValue;
}

class FrameFeatures {
  const FrameFeatures({
    required this.faceDetected,
    required this.poseDetected,
    this.earLeft,
    this.earRight,
    this.yaw,
    this.pitch,
    this.headOffset,
  });

  final bool faceDetected;
  final bool poseDetected;
  final double? earLeft;
  final double? earRight;
  final double? yaw;
  final double? pitch;
  final double? headOffset;
}

class FrameClassification {
  const FrameClassification({
    required this.eyeClosed,
    required this.headTurned,
    required this.postureDown,
    required this.userMissing,
    required this.state,
  });

  final bool eyeClosed;
  final bool headTurned;
  final bool postureDown;
  final bool userMissing;
  final RawFrameState state;
}

/// A deliberately memory-free baseline for Vision Lab.
///
/// Every result depends only on [features]. This class must not grow counters,
/// latches, cooldowns, filters, or voting windows; those belong to offline
/// post-processing. The live app continues to use `CompanionStateEvaluator`
/// and its existing temporal behavior.
class FrameClassifier {
  const FrameClassifier({
    this.closedEyeEar = 0.13,
    this.openEyeEar = 0.27,
    this.singleEyeClosedThreshold = 0.18,
    this.averageEyeClosedThreshold = 0.28,
    this.maxReliableHeadOffset = 55,
    this.maxReliableHeadPitch = 70,
    this.readingPitchThreshold = 25,
    this.readingClosedThresholdScale = 0.6,
    this.headTurnedThreshold = 55,
    this.postureDownPitchThreshold = 35,
  });

  // EAR normalization mirrors MediaPipeVisionManager.landmarkOpenProbability.
  final double closedEyeEar;
  final double openEyeEar;
  // Eye thresholds mirror EyeStateDetector's current-frame decision.
  final double singleEyeClosedThreshold;
  final double averageEyeClosedThreshold;
  final double maxReliableHeadOffset;
  final double maxReliableHeadPitch;
  final double readingPitchThreshold;
  final double readingClosedThresholdScale;
  final double headTurnedThreshold;

  /// This is intentionally a coarse, fixed pilot rule. The production posture
  /// detector uses calibration and temporal evidence, which are forbidden in
  /// this baseline. With the v1 CSV, a pose-only frame or a steep head pitch is
  /// the strongest single-frame posture evidence available.
  final double postureDownPitchThreshold;

  FrameClassification classify(
    FrameFeatures features, {
    double? leftOpenEyeEar,
    double? rightOpenEyeEar,
  }) {
    final userMissing = !features.faceDetected && !features.poseDetected;
    final headTurned =
        features.faceDetected &&
        features.headOffset != null &&
        features.headOffset! >= headTurnedThreshold;
    final postureDown =
        features.poseDetected &&
        (!features.faceDetected ||
            (features.pitch != null &&
                features.pitch!.abs() >= postureDownPitchThreshold));
    final eyeClosed = _isEyeClosed(
      features,
      leftOpenEyeEar: leftOpenEyeEar ?? openEyeEar,
      rightOpenEyeEar: rightOpenEyeEar ?? openEyeEar,
    );

    final state = switch ((userMissing, postureDown, headTurned, eyeClosed)) {
      (true, _, _, _) => RawFrameState.userMissing,
      (_, true, _, _) => RawFrameState.postureDown,
      (_, _, true, _) => RawFrameState.headTurned,
      (_, _, _, true) => RawFrameState.eyeClosed,
      _ => RawFrameState.normal,
    };

    return FrameClassification(
      eyeClosed: eyeClosed,
      headTurned: headTurned,
      postureDown: postureDown,
      userMissing: userMissing,
      state: state,
    );
  }

  bool _isEyeClosed(
    FrameFeatures features, {
    required double leftOpenEyeEar,
    required double rightOpenEyeEar,
  }) {
    final leftEar = features.earLeft;
    final rightEar = features.earRight;
    if (!features.faceDetected || leftEar == null || rightEar == null) {
      return false;
    }

    final headOffset = features.headOffset;
    final pitch = features.pitch?.abs();
    if ((headOffset != null && headOffset > maxReliableHeadOffset) ||
        (pitch != null && pitch > maxReliableHeadPitch)) {
      return false;
    }

    final thresholdScale = pitch != null && pitch >= readingPitchThreshold
        ? readingClosedThresholdScale
        : 1.0;
    final leftOpen = _earToOpenProbability(leftEar, leftOpenEyeEar);
    final rightOpen = _earToOpenProbability(rightEar, rightOpenEyeEar);
    final minimumOpen = math.min(leftOpen, rightOpen);
    final averageOpen = (leftOpen + rightOpen) / 2;

    return minimumOpen < singleEyeClosedThreshold * thresholdScale &&
        averageOpen < averageEyeClosedThreshold * thresholdScale;
  }

  double _earToOpenProbability(double ear, double calibratedOpenEyeEar) {
    final range = calibratedOpenEyeEar - closedEyeEar;
    if (range <= 0) return 0;
    return ((ear - closedEyeEar) / range).clamp(0.0, 1.0);
  }
}
