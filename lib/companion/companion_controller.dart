import '../vision/companion_state_evaluator.dart';
import '../vision/vision_result.dart';

class CompanionController {
  CompanionController({CompanionStateEvaluator? evaluator})
    : evaluator = evaluator ?? CompanionStateEvaluator();

  final CompanionStateEvaluator evaluator;

  int _closedEyeFrameCount = 0;
  int _distractedFrameCount = 0;
  int _postureDownFrameCount = 0;
  int? _lastPoseSequence;
  CompanionAnalysis? _lastAnalysis;

  int get closedEyeFrameCount => _closedEyeFrameCount;
  int get distractedFrameCount => _distractedFrameCount;
  int get postureDownFrameCount => _postureDownFrameCount;
  CompanionAnalysis? get lastAnalysis => _lastAnalysis;
  CompanionStatus get status => _lastAnalysis?.status ?? CompanionStatus.normal;

  CompanionAnalysis analyze(VisionResult result) {
    final poseSequence = result.poseSequence;
    final shouldUpdatePostureDown =
        poseSequence != null && poseSequence != _lastPoseSequence;
    final analysis = evaluator.evaluate(
      result: result,
      previousClosedFrameCount: _closedEyeFrameCount,
      previousDistractedFrameCount: _distractedFrameCount,
      previousPostureDownFrameCount: _postureDownFrameCount,
      shouldUpdatePostureDown: shouldUpdatePostureDown,
    );
    _closedEyeFrameCount = analysis.eyeResult.closedFrameCount;
    _distractedFrameCount = analysis.headOffsetResult.distractedFrameCount;
    _postureDownFrameCount = analysis.postureDownResult.downFrameCount;
    if (shouldUpdatePostureDown) {
      _lastPoseSequence = poseSequence;
    }
    _lastAnalysis = analysis;
    return analysis;
  }

  void reset() {
    _closedEyeFrameCount = 0;
    _distractedFrameCount = 0;
    _postureDownFrameCount = 0;
    _lastPoseSequence = null;
    _lastAnalysis = null;
    evaluator.reset();
  }
}
