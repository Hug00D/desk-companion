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
    this.singleEyeClosedThreshold = 0.18,
    this.averageEyeClosedThreshold = 0.28,
    this.attentionClosedFrames = 1,
    this.fatigueClosedFrames = 3,
    this.maxReliableHeadOffsetScore = 55,
    this.maxReliableHeadPitch = 70,
    this.readingPitchThreshold = 25,
    this.readingClosedThresholdScale = 0.6,
  });

  final double singleEyeClosedThreshold;
  final double averageEyeClosedThreshold;
  final int attentionClosedFrames;
  final int fatigueClosedFrames;
  final double maxReliableHeadOffsetScore;
  final double maxReliableHeadPitch;

  /// Reading tilts the head down far enough that the eyelids cover part of the
  /// iris, so the reported openness drops even with the eyes wide open. Past
  /// [readingPitchThreshold] degrees the closed thresholds tighten so half
  /// lidded eyes stop counting, while genuinely shut eyes still register on
  /// the usual frame count and keep drowsiness detection responsive.
  final double readingPitchThreshold;
  final double readingClosedThresholdScale;

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

    final headOffsetScore = result.headOffsetScore;
    final headPitch = result.headPitch?.abs();
    if ((headOffsetScore != null &&
            headOffsetScore > maxReliableHeadOffsetScore) ||
        (headPitch != null && headPitch > maxReliableHeadPitch)) {
      return const EyeDetectionResult(
        state: EyeState.noFace,
        closedFrameCount: 0,
      );
    }

    final isReadingPitch =
        headPitch != null && headPitch >= readingPitchThreshold;
    final singleThreshold = isReadingPitch
        ? singleEyeClosedThreshold * readingClosedThresholdScale
        : singleEyeClosedThreshold;
    final averageThreshold = isReadingPitch
        ? averageEyeClosedThreshold * readingClosedThresholdScale
        : averageEyeClosedThreshold;
    final minimumEyeOpen = result.leftEyeOpen! < result.rightEyeOpen!
        ? result.leftEyeOpen!
        : result.rightEyeOpen!;
    final averageEyeOpen = (result.leftEyeOpen! + result.rightEyeOpen!) / 2.0;
    final eyesClosed =
        minimumEyeOpen < singleThreshold && averageEyeOpen < averageThreshold;
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
