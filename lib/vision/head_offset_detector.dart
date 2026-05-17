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
    this.distractedThreshold = 25,
    this.distractedFrames = 2,
  });

  final double distractedThreshold;
  final int distractedFrames;

  HeadOffsetDetectionResult evaluate({
    required VisionResult result,
    required int previousDistractedFrameCount,
  }) {
    final score = result.headOffsetScore;
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
}
