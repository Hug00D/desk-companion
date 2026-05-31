import 'vision_result.dart';

enum PoseState { noPose, normal, tooClose, postureDown }

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
  const PoseStateDetector({this.tooCloseShoulderWidth = 780});

  final double tooCloseShoulderWidth;

  PoseDetectionResult evaluate({
    required VisionResult result,
    required double? postureDownScore,
    required int postureDownFrameCount,
    required bool isPostureDown,
  }) {
    final shoulderWidth = result.shoulderWidth;
    if (!result.hasPose || shoulderWidth == null) {
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

    if (shoulderWidth > tooCloseShoulderWidth) {
      return PoseDetectionResult(
        state: PoseState.tooClose,
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
}
