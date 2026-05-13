import 'vision_result.dart';

enum PoseState { noPose, normal, tooClose }

class PoseStateDetector {
  const PoseStateDetector({this.tooCloseShoulderWidth = 780});

  final double tooCloseShoulderWidth;

  PoseState evaluate(VisionResult result) {
    final shoulderWidth = result.shoulderWidth;
    if (!result.hasPose || shoulderWidth == null) {
      return PoseState.noPose;
    }

    if (shoulderWidth > tooCloseShoulderWidth) {
      return PoseState.tooClose;
    }

    return PoseState.normal;
  }
}
