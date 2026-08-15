import 'package:desk_companion/vision/companion_state_evaluator.dart';
import 'package:desk_companion/vision/posture_down_detector.dart';
import 'package:desk_companion/vision/vision_event.dart';
import 'package:desk_companion/vision/vision_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Companion status and cause mapping', () {
    test('drowsy remains a sleeping UI status with a drowsy cause', () {
      final evaluator = CompanionStateEvaluator(
        postureDownDetector: _FixedPostureDownDetector(
          const PostureDownDetectionResult(
            state: PostureDownState.normal,
            score: 11,
            downFrameCount: 0,
            headLowScore: 96,
            noseDropScore: 50,
            shoulderDropScore: 8,
            shoulderShrinkScore: 12,
            sideProneScore: 0,
          ),
        ),
      );

      final analysis = evaluator.evaluate(
        result: _visionResult(
          headPitch: 40,
          leftEyeOpen: 0.05,
          rightEyeOpen: 0.05,
        ),
        previousClosedFrameCount: 2,
        previousDistractedFrameCount: 0,
        isFreshPoseResult: true,
        observedAt: DateTime(2026, 8, 12, 10),
      );
      final event = VisionEvent.fromAnalysis(analysis);

      expect(analysis.status, CompanionStatus.sleeping);
      expect(analysis.cause, CompanionCause.drowsy);
      expect(event.type, VisionEventType.drowsyDetected);
      expect(event.toSignalsJson()['cause'], 'drowsy');
    });

    test('posture down remains a sleeping UI status with its own cause', () {
      final evaluator = CompanionStateEvaluator(
        postureDownDetector: _FixedPostureDownDetector(
          const PostureDownDetectionResult(
            state: PostureDownState.down,
            score: 100,
            downFrameCount: 2,
            headLowScore: 90,
            noseDropScore: 60,
            shoulderDropScore: 70,
            shoulderShrinkScore: 80,
            sideProneScore: 85,
          ),
        ),
      );

      final analysis = evaluator.evaluate(
        result: _visionResult(),
        previousClosedFrameCount: 0,
        previousDistractedFrameCount: 0,
        isFreshPoseResult: true,
        observedAt: DateTime(2026, 8, 12, 10),
      );
      final event = VisionEvent.fromAnalysis(analysis);

      expect(analysis.status, CompanionStatus.sleeping);
      expect(analysis.cause, CompanionCause.postureDown);
      expect(event.type, VisionEventType.postureDownDetected);
      expect(event.toSignalsJson()['cause'], 'postureDown');
    });
  });
}

VisionResult _visionResult({
  double headPitch = 0,
  double leftEyeOpen = 0.8,
  double rightEyeOpen = 0.8,
}) {
  return VisionResult(
    raw: const <dynamic, dynamic>{},
    hasPose: true,
    hasFace: true,
    imageWidth: 1000,
    imageHeight: 1000,
    poseSequence: 1,
    leftShoulderX: 300,
    leftShoulderY: 500,
    rightShoulderX: 700,
    rightShoulderY: 500,
    leftShoulderVisibility: 0.95,
    rightShoulderVisibility: 0.95,
    poseNoseX: 500,
    poseNoseY: 250,
    poseNoseVisibility: 0.95,
    poseLeftEyeVisibility: 0.95,
    poseRightEyeVisibility: 0.95,
    poseLeftEarVisibility: 0.95,
    poseRightEarVisibility: 0.95,
    leftEyeOpen: leftEyeOpen,
    rightEyeOpen: rightEyeOpen,
    headYaw: 0,
    headPitch: headPitch,
    headOffsetScore: 0,
    shoulderWidth: 400,
  );
}

class _FixedPostureDownDetector extends PostureDownDetector {
  _FixedPostureDownDetector(this.result);

  final PostureDownDetectionResult result;

  @override
  PostureDownDetectionResult evaluate({
    required VisionResult result,
    required bool shouldUpdate,
    DateTime? observedAt,
  }) {
    return this.result;
  }
}
