import 'vision_result.dart';

enum HeadOffsetState { unavailable, normal, distracted }

class HeadOffsetDetectionResult {
  const HeadOffsetDetectionResult({
    required this.state,
    required this.distractedFrameCount,
  });

  final HeadOffsetState state;
  final int distractedFrameCount;
}

class HeadOffsetDetector {
  HeadOffsetDetector({
    this.distractedThreshold = 55,
    this.distractedFrames = 4,
    this.angleChangeThreshold = 11,
    this.movementFrames = 3,
    this.movementHoldFrames = 2,
  });

  final double distractedThreshold;
  final int distractedFrames;
  final double angleChangeThreshold;
  final int movementFrames;
  final int movementHoldFrames;

  double? _lastYaw;
  double? _lastPitch;
  int _angleChangeFrameCount = 0;
  int _movementHoldFrameCount = 0;

  HeadOffsetDetectionResult evaluate({
    required VisionResult result,
    required int previousDistractedFrameCount,
  }) {
    final score = _score(result);

    if (result.isHeadOffsetCalibrating) {
      reset();
      return const HeadOffsetDetectionResult(
        state: HeadOffsetState.unavailable,
        distractedFrameCount: 0,
      );
    }

    if (!result.hasFace || score == null) {
      _clearTracking();
      return const HeadOffsetDetectionResult(
        state: HeadOffsetState.unavailable,
        distractedFrameCount: 0,
      );
    }

    final hasAngleMovement = _hasAngleMovement(result);
    if (hasAngleMovement) {
      _angleChangeFrameCount += 1;
      _movementHoldFrameCount = movementHoldFrames;
    } else if (_movementHoldFrameCount > 0) {
      _movementHoldFrameCount -= 1;
    } else {
      _angleChangeFrameCount = 0;
    }

    final isDistracted =
        score >= distractedThreshold &&
        _angleChangeFrameCount >= movementFrames;
    final distractedFrameCount = isDistracted
        ? previousDistractedFrameCount + 1
        : 0;

    if (distractedFrameCount >= distractedFrames) {
      return HeadOffsetDetectionResult(
        state: HeadOffsetState.distracted,
        distractedFrameCount: distractedFrameCount,
      );
    }

    return HeadOffsetDetectionResult(
      state: HeadOffsetState.normal,
      distractedFrameCount: distractedFrameCount,
    );
  }

  double? _score(VisionResult result) {
    return result.headOffsetScore;
  }

  bool _hasAngleMovement(VisionResult result) {
    final yaw = result.headYaw;
    final pitch = result.headPitch;
    if (yaw == null && pitch == null) return false;

    final previousYaw = _lastYaw;
    final previousPitch = _lastPitch;
    _lastYaw = yaw;
    _lastPitch = pitch;

    final yawDelta = yaw == null || previousYaw == null
        ? 0
        : (yaw - previousYaw).abs();
    final pitchDelta = pitch == null || previousPitch == null
        ? 0
        : (pitch - previousPitch).abs();

    return yawDelta >= angleChangeThreshold ||
        pitchDelta >= angleChangeThreshold;
  }

  void _clearTracking() {
    _lastYaw = null;
    _lastPitch = null;
    _angleChangeFrameCount = 0;
    _movementHoldFrameCount = 0;
  }

  void reset() {
    _clearTracking();
  }
}
