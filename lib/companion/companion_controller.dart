import '../vision/companion_state_evaluator.dart';
import '../vision/vision_result.dart';

class CompanionController {
  CompanionController({this.evaluator = const CompanionStateEvaluator()});

  final CompanionStateEvaluator evaluator;

  int _closedEyeFrameCount = 0;
  int _distractedFrameCount = 0;
  CompanionAnalysis? _lastAnalysis;

  int get closedEyeFrameCount => _closedEyeFrameCount;
  int get distractedFrameCount => _distractedFrameCount;
  CompanionAnalysis? get lastAnalysis => _lastAnalysis;
  CompanionStatus get status => _lastAnalysis?.status ?? CompanionStatus.normal;

  CompanionAnalysis analyze(VisionResult result) {
    final analysis = evaluator.evaluate(
      result: result,
      previousClosedFrameCount: _closedEyeFrameCount,
      previousDistractedFrameCount: _distractedFrameCount,
    );
    _closedEyeFrameCount = analysis.eyeResult.closedFrameCount;
    _distractedFrameCount = analysis.headOffsetResult.distractedFrameCount;
    _lastAnalysis = analysis;
    return analysis;
  }

  void reset() {
    _closedEyeFrameCount = 0;
    _distractedFrameCount = 0;
    _lastAnalysis = null;
  }
}
