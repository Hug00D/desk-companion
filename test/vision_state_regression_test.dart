import 'package:desk_companion/vision/companion_state_evaluator.dart';
import 'package:desk_companion/vision/eye_state_detector.dart';
import 'package:desk_companion/vision/posture_down_detector.dart';
import 'package:desk_companion/vision/vision_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fully missing user overrides a latched posture-down state', () {
    final evaluator = CompanionStateEvaluator(
      postureDownDetector: _StrongPostureDownDetector(),
    );

    var analysis = evaluator.evaluate(
      result: _visibleResult,
      previousClosedFrameCount: 0,
      previousDistractedFrameCount: 0,
      previousPostureDownFrameCount: 0,
      shouldUpdatePostureDown: true,
    );
    expect(analysis.status, CompanionStatus.postureDown);

    analysis = evaluator.evaluate(
      result: _awayResult,
      previousClosedFrameCount: analysis.eyeResult.closedFrameCount,
      previousDistractedFrameCount:
          analysis.headOffsetResult.distractedFrameCount,
      previousPostureDownFrameCount: analysis.postureDownResult.downFrameCount,
      shouldUpdatePostureDown: false,
    );
    expect(analysis.status, CompanionStatus.postureDown);

    analysis = evaluator.evaluate(
      result: _awayResult,
      previousClosedFrameCount: analysis.eyeResult.closedFrameCount,
      previousDistractedFrameCount:
          analysis.headOffsetResult.distractedFrameCount,
      previousPostureDownFrameCount: analysis.postureDownResult.downFrameCount,
      shouldUpdatePostureDown: false,
    );
    expect(analysis.status, CompanionStatus.userMissing);
  });

  test('zero eye values are ignored during calibration only', () {
    const detector = EyeStateDetector();
    var previousCount = 0;

    for (var i = 0; i < 4; i++) {
      final result = detector.evaluate(
        result: _calibratingClosedEyeResult,
        previousClosedFrameCount: previousCount,
      );
      expect(result.state, EyeState.open);
      expect(result.closedFrameCount, 0);
      previousCount = result.closedFrameCount;
    }

    EyeDetectionResult? result;
    for (var i = 0; i < 3; i++) {
      result = detector.evaluate(
        result: _closedEyeResult,
        previousClosedFrameCount: previousCount,
      );
      previousCount = result.closedFrameCount;
    }

    expect(result?.state, EyeState.fatigue);
  });
}

const _visibleResult = VisionResult(
  raw: <dynamic, dynamic>{},
  hasPose: true,
  hasFace: true,
  leftEyeOpen: 0.8,
  rightEyeOpen: 0.8,
  headOffsetScore: 0,
  headPitch: 0,
  shoulderWidth: 200,
);

const _awayResult = VisionResult(
  raw: <dynamic, dynamic>{},
  hasPose: false,
  hasFace: false,
);

const _calibratingClosedEyeResult = VisionResult(
  raw: <dynamic, dynamic>{},
  hasPose: true,
  hasFace: true,
  leftEyeOpen: 0,
  rightEyeOpen: 0,
  headOffsetScore: 0,
  headPitch: 0,
  isHeadOffsetCalibrating: true,
);

const _closedEyeResult = VisionResult(
  raw: <dynamic, dynamic>{},
  hasPose: true,
  hasFace: true,
  leftEyeOpen: 0,
  rightEyeOpen: 0,
  headOffsetScore: 0,
  headPitch: 0,
);

class _StrongPostureDownDetector extends PostureDownDetector {
  @override
  PostureDownDetectionResult evaluate({
    required VisionResult result,
    required int previousDownFrameCount,
    required bool shouldUpdate,
  }) {
    return PostureDownDetectionResult(
      state: PostureDownState.down,
      score: 100,
      downFrameCount: previousDownFrameCount + 1,
      headLowScore: 100,
      shoulderDropScore: 60,
      noseDropScore: 100,
      visibilityScore: 100,
      sideProneScore: 100,
      shoulderShrinkScore: 100,
    );
  }
}
