import 'package:desk_companion/companion/companion_controller.dart';
import 'package:desk_companion/vision/companion_state_evaluator.dart';
import 'package:desk_companion/vision/eye_state_detector.dart';
import 'package:desk_companion/vision/head_offset_detector.dart';
import 'package:desk_companion/vision/pose_state_detector.dart';
import 'package:desk_companion/vision/posture_down_detector.dart';
import 'package:desk_companion/vision/vision_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('temporal vision logic', () {
    test('head distraction uses 3-of-5 evidence and hysteresis recovery', () {
      final detector = HeadOffsetDetector();
      final start = DateTime(2026, 7, 12, 10);
      var previousCount = 0;

      for (var index = 0; index < 3; index++) {
        final result = detector.evaluate(
          result: _visionResult(headOffsetScore: 80),
          previousDistractedFrameCount: previousCount,
          observedAt: start.add(Duration(milliseconds: 800 * index)),
        );
        previousCount = result.distractedFrameCount;
        if (index < 2) expect(result.state, HeadOffsetState.normal);
        if (index == 2) expect(result.state, HeadOffsetState.distracted);
      }

      for (var index = 3; index < 5; index++) {
        final result = detector.evaluate(
          result: _visionResult(headOffsetScore: 0),
          previousDistractedFrameCount: previousCount,
          observedAt: start.add(Duration(milliseconds: 800 * index)),
        );
        previousCount = result.distractedFrameCount;
        if (index == 3) expect(result.state, HeadOffsetState.distracted);
        if (index == 4) expect(result.state, HeadOffsetState.normal);
      }
    });

    test('drowsy requires closed-eye evidence', () {
      const detector = PoseStateDetector();
      const posture = PostureDownDetectionResult(
        state: PostureDownState.normal,
        score: 34,
        downFrameCount: 0,
        headLowScore: 80,
        noseDropScore: 85,
        shoulderDropScore: 20,
        shoulderShrinkScore: 20,
      );
      final result = _visionResult(headPitch: 40);

      final eyesOpen = detector.evaluate(
        result: result,
        postureDownResult: posture,
        postureDownFrameCount: 0,
        isPostureDown: false,
        eyeState: EyeState.open,
      );
      final eyesClosed = detector.evaluate(
        result: result,
        postureDownResult: posture,
        postureDownFrameCount: 0,
        isPostureDown: false,
        eyeState: EyeState.fatigue,
      );

      expect(eyesOpen.state, PoseState.normal);
      expect(eyesClosed.state, PoseState.drowsy);
    });

    test('posture transition suppresses generic eye fatigue warning', () {
      final controller = CompanionController();
      final start = DateTime(2026, 7, 12, 10, 30);

      for (var sequence = 1; sequence <= 6; sequence++) {
        controller.analyze(
          _visionResult(poseSequence: sequence),
          observedAt: start.add(Duration(milliseconds: 800 * sequence)),
        );
      }

      final transition = controller.analyze(
        _postureTransitionResult(poseSequence: 7),
        observedAt: start.add(const Duration(milliseconds: 5600)),
      );

      expect(transition.postureDownResult.downFrameCount, 1);
      expect(transition.eyeResult.state, EyeState.attention);
      expect(transition.status, CompanionStatus.normal);
    });

    test(
      'quick camera exit does not confirm posture down from missing data',
      () {
        final controller = CompanionController();
        final start = DateTime(2026, 7, 12, 10, 45);

        for (var sequence = 1; sequence <= 6; sequence++) {
          controller.analyze(
            _visionResult(poseSequence: sequence),
            observedAt: start.add(Duration(milliseconds: 800 * sequence)),
          );
        }

        final transition = controller.analyze(
          _postureTransitionResult(poseSequence: 7),
          observedAt: start.add(const Duration(milliseconds: 5600)),
        );
        expect(transition.postureDownResult.downFrameCount, 1);

        for (var sequence = 8; sequence <= 12; sequence++) {
          final missing = controller.analyze(
            _missingUserResult(poseSequence: sequence),
            observedAt: start.add(Duration(milliseconds: 800 * sequence)),
          );
          expect(missing.status, isNot(CompanionStatus.postureDown));
        }
      },
    );

    test('stale pose cannot confirm posture down', () {
      final controller = CompanionController();
      final start = DateTime(2026, 7, 12, 10);

      for (var sequence = 1; sequence <= 6; sequence++) {
        controller.analyze(
          _visionResult(poseSequence: sequence),
          observedAt: start.add(Duration(milliseconds: 800 * sequence)),
        );
      }

      final firstCandidate = controller.analyze(
        _postureDownResult(poseSequence: 7),
        observedAt: start.add(const Duration(milliseconds: 5600)),
      );
      expect(firstCandidate.postureDownResult.downFrameCount, 1);
      expect(firstCandidate.status, isNot(CompanionStatus.postureDown));

      for (var index = 0; index < 8; index++) {
        final stale = controller.analyze(
          _postureDownResult(poseSequence: 7),
          observedAt: start.add(Duration(milliseconds: 5700 + index * 100)),
        );
        expect(stale.postureDownResult.downFrameCount, 1);
        expect(stale.status, isNot(CompanionStatus.postureDown));
      }

      final confirmed = controller.analyze(
        _postureDownResult(poseSequence: 8),
        observedAt: start.add(const Duration(milliseconds: 6400)),
      );
      expect(confirmed.postureDownResult.downFrameCount, 2);
      expect(confirmed.status, CompanionStatus.postureDown);
    });

    test('confirmed posture clears after two fresh recovered poses', () {
      final controller = CompanionController();
      final start = DateTime(2026, 7, 12, 11);

      for (var sequence = 1; sequence <= 6; sequence++) {
        controller.analyze(
          _visionResult(poseSequence: sequence),
          observedAt: start.add(Duration(milliseconds: 800 * sequence)),
        );
      }
      for (var sequence = 7; sequence <= 9; sequence++) {
        controller.analyze(
          _postureDownResult(poseSequence: sequence),
          observedAt: start.add(Duration(milliseconds: 800 * sequence)),
        );
      }

      final firstRecovery = controller.analyze(
        _visionResult(poseSequence: 10),
        observedAt: start.add(const Duration(milliseconds: 8000)),
      );
      final secondRecovery = controller.analyze(
        _visionResult(poseSequence: 11),
        observedAt: start.add(const Duration(milliseconds: 8800)),
      );

      expect(firstRecovery.status, CompanionStatus.postureDown);
      expect(secondRecovery.status, CompanionStatus.normal);
    });

    test('latched posture recovers when face and head are stable', () {
      final evaluator = CompanionStateEvaluator(
        postureDownDetector: _QueuedPostureDownDetector([
          const PostureDownDetectionResult(
            state: PostureDownState.down,
            score: 100,
            downFrameCount: 2,
            headLowScore: 100,
            noseDropScore: 100,
            sideProneScore: 100,
            shoulderDropScore: 100,
            shoulderShrinkScore: 80,
          ),
          const PostureDownDetectionResult(
            state: PostureDownState.normal,
            score: 34,
            downFrameCount: 0,
            headLowScore: 0,
            noseDropScore: 0,
            sideProneScore: 0,
            shoulderDropScore: 100,
            shoulderShrinkScore: 0,
          ),
        ]),
      );
      final start = DateTime(2026, 7, 12, 11, 30);

      final latched = evaluator.evaluate(
        result: _visionResult(poseSequence: 1),
        previousClosedFrameCount: 0,
        previousDistractedFrameCount: 0,
        isFreshPoseResult: true,
        observedAt: start,
      );
      final recovered = evaluator.evaluate(
        result: _visionResult(
          poseSequence: 2,
          headOffsetScore: 11.8,
          headPitch: -11.6,
        ),
        previousClosedFrameCount: 0,
        previousDistractedFrameCount: 0,
        isFreshPoseResult: true,
        observedAt: start.add(const Duration(milliseconds: 800)),
      );

      expect(latched.status, CompanionStatus.postureDown);
      expect(recovered.postureDownResult.shoulderDropScore, greaterThan(90));
      expect(recovered.status, CompanionStatus.normal);
    });
  });
}

VisionResult _visionResult({
  int poseSequence = 1,
  double headOffsetScore = 0,
  double headPitch = 0,
}) {
  return VisionResult(
    raw: const <dynamic, dynamic>{},
    hasPose: true,
    hasFace: true,
    imageWidth: 1000,
    imageHeight: 1000,
    poseSequence: poseSequence,
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
    leftEyeOpen: 0.8,
    rightEyeOpen: 0.8,
    headYaw: 0,
    headPitch: headPitch,
    headOffsetScore: headOffsetScore,
    shoulderWidth: 400,
  );
}

VisionResult _postureDownResult({required int poseSequence}) {
  return VisionResult(
    raw: const <dynamic, dynamic>{},
    hasPose: true,
    hasFace: false,
    imageWidth: 1000,
    imageHeight: 1000,
    poseSequence: poseSequence,
    leftShoulderX: 375,
    leftShoulderY: 600,
    rightShoulderX: 625,
    rightShoulderY: 600,
    leftShoulderVisibility: 0.9,
    rightShoulderVisibility: 0.9,
    poseNoseX: 500,
    poseNoseY: 580,
    poseNoseVisibility: 0.3,
    poseLeftEyeVisibility: 0.2,
    poseRightEyeVisibility: 0.2,
    poseLeftEarVisibility: 0.3,
    poseRightEarVisibility: 0.3,
    shoulderWidth: 250,
  );
}

VisionResult _postureTransitionResult({required int poseSequence}) {
  return VisionResult(
    raw: const <dynamic, dynamic>{},
    hasPose: true,
    hasFace: true,
    imageWidth: 1000,
    imageHeight: 1000,
    poseSequence: poseSequence,
    leftShoulderX: 375,
    leftShoulderY: 600,
    rightShoulderX: 625,
    rightShoulderY: 600,
    leftShoulderVisibility: 0.9,
    rightShoulderVisibility: 0.9,
    poseNoseX: 500,
    poseNoseY: 580,
    poseNoseVisibility: 0.8,
    poseLeftEyeVisibility: 0.8,
    poseRightEyeVisibility: 0.8,
    poseLeftEarVisibility: 0.8,
    poseRightEarVisibility: 0.8,
    leftEyeOpen: 0.05,
    rightEyeOpen: 0.05,
    headYaw: 0,
    headPitch: 40,
    headOffsetScore: 0,
    shoulderWidth: 250,
  );
}

VisionResult _missingUserResult({required int poseSequence}) {
  return VisionResult(
    raw: const <dynamic, dynamic>{},
    hasPose: false,
    hasFace: false,
    poseSequence: poseSequence,
  );
}

class _QueuedPostureDownDetector extends PostureDownDetector {
  _QueuedPostureDownDetector(this.results);

  final List<PostureDownDetectionResult> results;

  @override
  PostureDownDetectionResult evaluate({
    required VisionResult result,
    required bool shouldUpdate,
    DateTime? observedAt,
  }) {
    return results.removeAt(0);
  }
}
