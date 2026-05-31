import 'vision_result.dart';

enum PoseState { noPose, detected }

class PoseStateDetector {
  const PoseStateDetector();

  PoseState evaluate(VisionResult result) {
    if (!result.hasPose || result.shoulderWidth == null) {
      return PoseState.noPose;
    }

    return PoseState.detected;
  }
}
