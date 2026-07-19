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

    test('sustained steady gaze releases distraction until head re-centers', () {
      final detector = HeadOffsetDetector();
      final start = DateTime(2026, 7, 12, 14);
      var frame = 0;
      var previousCount = 0;

      HeadOffsetDetectionResult step(double score) {
        final result = detector.evaluate(
          result: _visionResult(headOffsetScore: score),
          previousDistractedFrameCount: previousCount,
          observedAt: start.add(Duration(milliseconds: 800 * frame++)),
        );
        previousCount = result.distractedFrameCount;
        return result;
      }

      for (var index = 0; index < 3; index++) {
        step(80);
      }
      expect(step(80).state, HeadOffsetState.distracted);

      // Keep staring at the same off-center spot for over 8 seconds.
      HeadOffsetDetectionResult? released;
      for (var index = 0; index < 11; index++) {
        released = step(80);
      }
      expect(released!.state, HeadOffsetState.normal);

      // Still off-center: must not re-enter distraction before re-centering.
      expect(step(80).state, HeadOffsetState.normal);
      expect(step(80).state, HeadOffsetState.normal);

      // Head returns to baseline, re-arming the detector.
      expect(step(0).state, HeadOffsetState.normal);

      // A fresh rapid turn is distraction again.
      HeadOffsetDetectionResult? reentered;
      for (var index = 0; index < 3; index++) {
        reentered = step(80);
      }
      expect(reentered!.state, HeadOffsetState.distracted);
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

    test('sustained full absence becomes userMissing instead of distracted', () {
      final controller = CompanionController();
      final start = DateTime(2026, 7, 12, 12);
      var sequence = 0;

      for (var index = 0; index < 6; index++) {
        controller.analyze(
          _visionResult(poseSequence: ++sequence),
          observedAt: start.add(Duration(milliseconds: 800 * sequence)),
        );
      }
      for (var index = 0; index < 3; index++) {
        controller.analyze(
          _visionResult(poseSequence: ++sequence, headOffsetScore: 80),
          observedAt: start.add(Duration(milliseconds: 800 * sequence)),
        );
      }
      expect(controller.status, CompanionStatus.distracted);

      CompanionStatus? finalStatus;
      for (var index = 0; index < 10; index++) {
        final analysis = controller.analyze(
          _missingUserResult(poseSequence: ++sequence),
          observedAt: start.add(Duration(milliseconds: 800 * sequence)),
        );
        finalStatus = analysis.status;
        expect(analysis.status, isNot(CompanionStatus.distracted));
      }

      expect(finalStatus, CompanionStatus.userMissing);
    });

    test('sideways exit without downward motion never votes posture down', () {
      final controller = CompanionController();
      final start = DateTime(2026, 7, 12, 13);
      var sequence = 0;

      for (var index = 0; index < 6; index++) {
        controller.analyze(
          _visionResult(poseSequence: ++sequence),
          observedAt: start.add(Duration(milliseconds: 800 * sequence)),
        );
      }

      for (var index = 0; index < 4; index++) {
        final analysis = controller.analyze(
          _sidewaysExitResult(poseSequence: ++sequence),
          observedAt: start.add(Duration(milliseconds: 800 * sequence)),
        );
        expect(analysis.postureDownResult.downFrameCount, 0);
        expect(analysis.status, isNot(CompanionStatus.postureDown));
        expect(analysis.status, isNot(CompanionStatus.distracted));
      }
    });

    test('standing up with flickering landmarks never votes posture down', () {
      final controller = CompanionController();
      final start = DateTime(2026, 7, 12, 15);
      var sequence = 0;

      for (var index = 0; index < 6; index++) {
        controller.analyze(
          _visionResult(poseSequence: ++sequence),
          observedAt: start.add(Duration(milliseconds: 800 * sequence)),
        );
      }

      // Head and shoulders rise as the user stands up.
      controller.analyze(
        _standingUpResult(poseSequence: ++sequence),
        observedAt: start.add(Duration(milliseconds: 800 * sequence)),
      );

      // Hallucinated landmarks then jump between extremes.
      for (var index = 0; index < 6; index++) {
        final analysis = controller.analyze(
          index.isEven
              ? _garbageLowPoseResult(poseSequence: ++sequence)
              : _garbageHighPoseResult(poseSequence: ++sequence),
          observedAt: start.add(Duration(milliseconds: 800 * sequence)),
        );
        expect(analysis.postureDownResult.downFrameCount, 0);
        expect(analysis.status, isNot(CompanionStatus.postureDown));
      }
    });

    test('frame exit without prior descent cannot vote posture down', () {
      final controller = CompanionController();
      final start = DateTime(2026, 7, 12, 16);
      var sequence = 0;

      for (var index = 0; index < 6; index++) {
        controller.analyze(
          _visionResult(poseSequence: ++sequence),
          observedAt: start.add(Duration(milliseconds: 800 * sequence)),
        );
      }

      // Walking out: hallucinated low-visibility landmarks jump downward,
      // but no descent was ever observed while tracking was reliable.
      for (var index = 0; index < 6; index++) {
        final analysis = controller.analyze(
          _garbageLowPoseResult(poseSequence: ++sequence),
          observedAt: start.add(Duration(milliseconds: 800 * sequence)),
        );
        expect(analysis.postureDownResult.downFrameCount, 0);
        expect(analysis.status, isNot(CompanionStatus.postureDown));
      }
    });

    test('sudden collapse confirms even when tracking degrades mid-fall', () {
      final controller = CompanionController();
      final start = DateTime(2026, 7, 12, 16, 30);
      var sequence = 0;

      for (var index = 0; index < 6; index++) {
        controller.analyze(
          _visionResult(poseSequence: ++sequence),
          observedAt: start.add(Duration(milliseconds: 800 * sequence)),
        );
      }

      // The fall starts while the face is still tracked (reliable descent).
      final falling = controller.analyze(
        _postureTransitionResult(poseSequence: ++sequence),
        observedAt: start.add(Duration(milliseconds: 800 * sequence)),
      );
      expect(falling.postureDownResult.downFrameCount, 1);

      // Tracking then degrades into hallucinated landmarks; the pre-loss
      // descent window still lets the collapsed frames finish confirmation.
      final collapsed = controller.analyze(
        _garbageLowPoseResult(poseSequence: ++sequence),
        observedAt: start.add(Duration(milliseconds: 800 * sequence)),
      );
      expect(collapsed.status, CompanionStatus.postureDown);
    });

    test('latched posture force-releases after sustained upright face', () {
      final heldDown = const PostureDownDetectionResult(
        state: PostureDownState.down,
        score: 100,
        downFrameCount: 2,
        headLowScore: 100,
        noseDropScore: 100,
        sideProneScore: 100,
        shoulderDropScore: 100,
        shoulderShrinkScore: 80,
      );
      final evaluator = CompanionStateEvaluator(
        postureDownDetector: _QueuedPostureDownDetector(
          List.filled(5, heldDown, growable: true),
        ),
      );
      final start = DateTime(2026, 7, 12, 12, 30);

      final statuses = <CompanionStatus>[];
      for (var index = 0; index < 5; index++) {
        final analysis = evaluator.evaluate(
          result: _visionResult(poseSequence: index + 1),
          previousClosedFrameCount: 0,
          previousDistractedFrameCount: 0,
          isFreshPoseResult: true,
          observedAt: start.add(Duration(milliseconds: 800 * index)),
        );
        statuses.add(analysis.status);
      }

      expect(statuses.sublist(0, 4), everyElement(CompanionStatus.postureDown));
      expect(statuses.last, CompanionStatus.normal);
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

VisionResult _sidewaysExitResult({required int poseSequence}) {
  return VisionResult(
    raw: const <dynamic, dynamic>{},
    hasPose: true,
    hasFace: false,
    imageWidth: 1000,
    imageHeight: 1000,
    poseSequence: poseSequence,
    leftShoulderX: 375,
    leftShoulderY: 500,
    rightShoulderX: 625,
    rightShoulderY: 500,
    leftShoulderVisibility: 0.85,
    rightShoulderVisibility: 0.4,
    poseNoseX: 400,
    poseNoseY: 250,
    poseNoseVisibility: 0.5,
    poseLeftEyeVisibility: 0.4,
    poseRightEyeVisibility: 0.4,
    poseLeftEarVisibility: 0.4,
    poseRightEarVisibility: 0.4,
    shoulderWidth: 250,
  );
}

VisionResult _standingUpResult({required int poseSequence}) {
  return VisionResult(
    raw: const <dynamic, dynamic>{},
    hasPose: true,
    hasFace: true,
    imageWidth: 1000,
    imageHeight: 1000,
    poseSequence: poseSequence,
    leftShoulderX: 300,
    leftShoulderY: 400,
    rightShoulderX: 700,
    rightShoulderY: 400,
    leftShoulderVisibility: 0.9,
    rightShoulderVisibility: 0.9,
    poseNoseX: 500,
    poseNoseY: 100,
    poseNoseVisibility: 0.85,
    poseLeftEyeVisibility: 0.8,
    poseRightEyeVisibility: 0.8,
    poseLeftEarVisibility: 0.8,
    poseRightEarVisibility: 0.8,
    leftEyeOpen: 0.8,
    rightEyeOpen: 0.8,
    headYaw: 0,
    headPitch: 0,
    headOffsetScore: 0,
    shoulderWidth: 400,
  );
}

VisionResult _garbageLowPoseResult({required int poseSequence}) {
  return VisionResult(
    raw: const <dynamic, dynamic>{},
    hasPose: true,
    hasFace: false,
    imageWidth: 1000,
    imageHeight: 1000,
    poseSequence: poseSequence,
    leftShoulderX: 400,
    leftShoulderY: 650,
    rightShoulderX: 650,
    rightShoulderY: 650,
    leftShoulderVisibility: 0.4,
    rightShoulderVisibility: 0.4,
    poseNoseX: 500,
    poseNoseY: 700,
    poseNoseVisibility: 0.2,
    poseLeftEyeVisibility: 0.2,
    poseRightEyeVisibility: 0.2,
    poseLeftEarVisibility: 0.2,
    poseRightEarVisibility: 0.2,
    shoulderWidth: 250,
  );
}

VisionResult _garbageHighPoseResult({required int poseSequence}) {
  return VisionResult(
    raw: const <dynamic, dynamic>{},
    hasPose: true,
    hasFace: false,
    imageWidth: 1000,
    imageHeight: 1000,
    poseSequence: poseSequence,
    leftShoulderX: 350,
    leftShoulderY: 380,
    rightShoulderX: 680,
    rightShoulderY: 380,
    leftShoulderVisibility: 0.4,
    rightShoulderVisibility: 0.4,
    poseNoseX: 500,
    poseNoseY: 120,
    poseNoseVisibility: 0.2,
    poseLeftEyeVisibility: 0.2,
    poseRightEyeVisibility: 0.2,
    poseLeftEarVisibility: 0.2,
    poseRightEarVisibility: 0.2,
    shoulderWidth: 330,
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
