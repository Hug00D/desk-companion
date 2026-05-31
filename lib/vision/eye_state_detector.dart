import 'vision_result.dart';

enum EyeState { noFace, open, attention, fatigue }

class EyeDetectionResult {
  const EyeDetectionResult({
    required this.state,
    required this.closedFrameCount,
  });

  final EyeState state;
  final int closedFrameCount;
}

class EyeStateDetector {
  const EyeStateDetector({
    this.eyeClosedThreshold = 0.2,
    this.attentionClosedFrames = 1,
    this.fatigueClosedFrames = 3,
    this.maxReliableHeadYaw = 25,
    this.maxReliableHeadPitch = 28,
  });

  final double eyeClosedThreshold;
  final int attentionClosedFrames;
  final int fatigueClosedFrames;
  final double maxReliableHeadYaw;
  final double maxReliableHeadPitch;

  EyeDetectionResult evaluate({
    required VisionResult result,
    required int previousClosedFrameCount,
  }) {
    if (!result.hasFace || !result.hasEyeData) {
      return const EyeDetectionResult(
        state: EyeState.noFace,
        closedFrameCount: 0,
      );
    }

    final headYaw = result.headYaw?.abs();
    final headPitch = result.headPitch?.abs();
    if ((headYaw != null && headYaw > maxReliableHeadYaw) ||
        (headPitch != null && headPitch > maxReliableHeadPitch)) {
      return const EyeDetectionResult(
        state: EyeState.noFace,
        closedFrameCount: 0,
      );
    }

    final eyesClosed =
        result.leftEyeOpen! < eyeClosedThreshold &&
        result.rightEyeOpen! < eyeClosedThreshold;
    final closedFrameCount = eyesClosed ? previousClosedFrameCount + 1 : 0;

    if (closedFrameCount >= fatigueClosedFrames) {
      return EyeDetectionResult(
        state: EyeState.fatigue,
        closedFrameCount: closedFrameCount,
      );
    }

    if (closedFrameCount >= attentionClosedFrames) {
      return EyeDetectionResult(
        state: EyeState.attention,
        closedFrameCount: closedFrameCount,
      );
    }

    return EyeDetectionResult(
      state: EyeState.open,
      closedFrameCount: closedFrameCount,
    );
  }
}
