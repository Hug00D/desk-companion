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
    this.strongDistractedThreshold = 72,
    this.distractedFrames = 5,
    this.missingFaceHoldFrames = 3,
  });

  final double distractedThreshold;
  final double strongDistractedThreshold;
  final int distractedFrames;
  final int missingFaceHoldFrames;

  double? _lastScore;
  int _missingFaceFrameCount = 0;

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
      _missingFaceFrameCount += 1;
      final shouldHoldDistracted = _lastScore != null &&
          _missingFaceFrameCount <= missingFaceHoldFrames &&
          _lastScore! >= strongDistractedThreshold &&
          previousDistractedFrameCount >= distractedFrames;

      if (shouldHoldDistracted) {
        final distractedFrameCount = previousDistractedFrameCount + 1;
        return HeadOffsetDetectionResult(
          state: distractedFrameCount >= distractedFrames
              ? HeadOffsetState.distracted
              : HeadOffsetState.normal,
          distractedFrameCount: distractedFrameCount,
        );
      }

      return const HeadOffsetDetectionResult(
        state: HeadOffsetState.unavailable,
        distractedFrameCount: 0,
      );
    }

    _lastScore = score;
    _missingFaceFrameCount = 0;

    final isDistracted = score >= distractedThreshold;
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

  void reset() {
    _lastScore = null;
    _missingFaceFrameCount = 0;
  }
}
