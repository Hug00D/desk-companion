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
  const HeadOffsetDetector({
    this.distractedThreshold = 45,
    this.distractedFrames = 3,
  });

  final double distractedThreshold;
  final int distractedFrames;

  HeadOffsetDetectionResult evaluate({
    required VisionResult result,
    required int previousDistractedFrameCount,
  }) {
    final score = _score(result);
    if (!result.hasFace || result.isHeadOffsetCalibrating || score == null) {
      return const HeadOffsetDetectionResult(
        state: HeadOffsetState.unavailable,
        distractedFrameCount: 0,
      );
    }

    final isDistracted = score > distractedThreshold;
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
}
