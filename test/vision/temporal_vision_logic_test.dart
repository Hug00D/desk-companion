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

    test('sustained large head offset remains distracted', () {
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

      // A real sustained turn must not become normal merely because it is stable.
      HeadOffsetDetectionResult? sustained;
      for (var index = 0; index < 11; index++) {
        sustained = step(80);
      }
      expect(sustained!.state, HeadOffsetState.distracted);
    });

    test('small page-to-page head movement is tolerated', () {
      final detector = HeadOffsetDetector();
      final start = DateTime(2026, 7, 12, 14, 30);
      var previousCount = 0;
      final scores = <double>[18, 32, 48, 52, 45, 28, 50, 34];

      for (var index = 0; index < scores.length; index++) {
        final result = detector.evaluate(
          result: _visionResult(headOffsetScore: scores[index]),
          previousDistractedFrameCount: previousCount,
          observedAt: start.add(Duration(milliseconds: 800 * index)),
        );
        previousCount = result.distractedFrameCount;
        expect(result.state, HeadOffsetState.normal);
      }
    });

    test('drowsy requires closed-eye evidence beyond reading posture', () {
      const detector = PoseStateDetector();
      const protectedReadingPosture = PostureDownDetectionResult(
        state: PostureDownState.normal,
        score: 11,
        downFrameCount: 0,
        headLowScore: 80,
        noseDropScore: 50,
        shoulderDropScore: 8,
        shoulderShrinkScore: 12,
        sideProneScore: 0,
      );
      const extremeHeadLowPosture = PostureDownDetectionResult(
        state: PostureDownState.normal,
        score: 11,
        downFrameCount: 0,
        headLowScore: 96,
        noseDropScore: 50,
        shoulderDropScore: 8,
        shoulderShrinkScore: 12,
        sideProneScore: 0,
      );
      final result = _visionResult(headPitch: 40);

      final eyesOpen = detector.evaluate(
        result: result,
        postureDownResult: extremeHeadLowPosture,
        postureDownFrameCount: 0,
        isPostureDown: false,
        eyeState: EyeState.open,
      );
      final protectedReading = detector.evaluate(
        result: result,
        postureDownResult: protectedReadingPosture,
        postureDownFrameCount: 0,
        isPostureDown: false,
        eyeState: EyeState.fatigue,
      );
      final eyesClosed = detector.evaluate(
        result: result,
        postureDownResult: extremeHeadLowPosture,
        postureDownFrameCount: 0,
        isPostureDown: false,
        eyeState: EyeState.fatigue,
      );
      final eyesClosedWithOppositePitchSign = detector.evaluate(
        result: _visionResult(headPitch: -40),
        postureDownResult: extremeHeadLowPosture,
        postureDownFrameCount: 0,
        isPostureDown: false,
        eyeState: EyeState.fatigue,
      );

      expect(eyesOpen.state, PoseState.normal);
      expect(protectedReading.state, PoseState.normal);
      expect(eyesClosed.state, PoseState.drowsy);
      expect(eyesClosedWithOppositePitchSign.state, PoseState.drowsy);
    });

    test('stable reading head drop does not become sleeping on face loss', () {
      final evaluator = CompanionStateEvaluator(
        postureDownDetector: _QueuedPostureDownDetector([
          const PostureDownDetectionResult(
            state: PostureDownState.normal,
            score: 11,
            downFrameCount: 0,
            headLowScore: 93,
            noseDropScore: 50,
            shoulderDropScore: 8,
            shoulderShrinkScore: 12,
            sideProneScore: 0,
          ),
          const PostureDownDetectionResult(
            state: PostureDownState.normal,
            score: 11,
            downFrameCount: 0,
            headLowScore: 93,
            noseDropScore: 50,
            shoulderDropScore: 8,
            shoulderShrinkScore: 12,
            sideProneScore: 0,
          ),
        ]),
      );
      final start = DateTime(2026, 7, 12, 10, 20);

      final reading = evaluator.evaluate(
        result: _visionResult(
          poseSequence: 1,
          leftEyeOpen: 0.05,
          rightEyeOpen: 0.05,
        ),
        previousClosedFrameCount: 2,
        previousDistractedFrameCount: 0,
        isFreshPoseResult: true,
        observedAt: start,
      );
      final faceLost = evaluator.evaluate(
        result: _sidewaysExitResult(poseSequence: 2),
        previousClosedFrameCount: reading.eyeResult.closedFrameCount,
        previousDistractedFrameCount: 0,
        isFreshPoseResult: true,
        observedAt: start.add(const Duration(milliseconds: 800)),
      );

      expect(reading.eyeResult.state, EyeState.fatigue);
      expect(reading.status, CompanionStatus.fatigue);
      expect(faceLost.status, isNot(CompanionStatus.sleeping));
    });

    test('asymmetric but jointly closed eyes can accumulate fatigue', () {
      const detector = EyeStateDetector();
      var closedFrames = 0;

      for (var index = 0; index < 3; index++) {
        final result = detector.evaluate(
          result: _visionResult(leftEyeOpen: 0.12, rightEyeOpen: 0.36),
          previousClosedFrameCount: closedFrames,
        );
        closedFrames = result.closedFrameCount;
        if (index < 2) expect(result.state, isNot(EyeState.fatigue));
        if (index == 2) expect(result.state, EyeState.fatigue);
      }
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

    test('strong posture candidate delays eye warnings', () {
      final postureCandidate = const PostureDownDetectionResult(
        state: PostureDownState.normal,
        score: 80,
        downFrameCount: 1,
        headLowScore: 20,
        noseDropScore: 10,
        shoulderDropScore: 60,
        shoulderShrinkScore: 20,
        sideProneScore: 20,
      );
      final start = DateTime(2026, 7, 12, 10, 35);

      CompanionAnalysis analyzeWithClosedFrames(int previousClosedFrames) {
        final evaluator = CompanionStateEvaluator(
          postureDownDetector: _QueuedPostureDownDetector([postureCandidate]),
        );
        return evaluator.evaluate(
          result: _visionResult(
            poseSequence: 1,
            leftEyeOpen: 0.05,
            rightEyeOpen: 0.05,
          ),
          previousClosedFrameCount: previousClosedFrames,
          previousDistractedFrameCount: 0,
          isFreshPoseResult: true,
          observedAt: start,
        );
      }

      final attention = analyzeWithClosedFrames(0);
      final shortFatigue = analyzeWithClosedFrames(2);
      final longFatigue = analyzeWithClosedFrames(4);

      expect(attention.eyeResult.state, EyeState.attention);
      expect(attention.status, CompanionStatus.normal);
      expect(shortFatigue.eyeResult.state, EyeState.fatigue);
      expect(shortFatigue.status, CompanionStatus.normal);
      expect(longFatigue.eyeResult.state, EyeState.fatigue);
      expect(longFatigue.status, CompanionStatus.fatigue);
    });

    test('nose drop is weighted down for posture scoring', () {
      final detector = PostureDownDetector();
      final start = DateTime(2026, 7, 12, 10, 40);

      for (var sequence = 1; sequence <= 6; sequence++) {
        detector.evaluate(
          result: _visionResult(poseSequence: sequence),
          shouldUpdate: true,
          observedAt: start.add(Duration(milliseconds: 800 * sequence)),
        );
      }

      final readingPosture = detector.evaluate(
        result: _readingHeadDownResult(poseSequence: 7),
        shouldUpdate: true,
        observedAt: start.add(const Duration(milliseconds: 5600)),
      );

      expect(readingPosture.noseDropScore, 50);
      expect(readingPosture.state, PostureDownState.normal);
      expect(readingPosture.downFrameCount, 0);
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
          expect(missing.status, isNot(CompanionStatus.sleeping));
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
      expect(firstCandidate.status, isNot(CompanionStatus.sleeping));

      for (var index = 0; index < 8; index++) {
        final stale = controller.analyze(
          _postureDownResult(poseSequence: 7),
          observedAt: start.add(Duration(milliseconds: 5700 + index * 100)),
        );
        expect(stale.postureDownResult.downFrameCount, 1);
        expect(stale.status, isNot(CompanionStatus.sleeping));
      }

      final confirmed = controller.analyze(
        _postureDownResult(poseSequence: 8),
        observedAt: start.add(const Duration(milliseconds: 6400)),
      );
      expect(confirmed.postureDownResult.downFrameCount, 2);
      expect(confirmed.status, CompanionStatus.sleeping);
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

      expect(firstRecovery.status, CompanionStatus.sleeping);
      expect(secondRecovery.status, CompanionStatus.normal);
    });

    test(
      'sustained full absence becomes userMissing instead of distracted',
      () {
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
      },
    );

    test('side face loss becomes distraction without voting sleep', () {
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
        expect(analysis.status, isNot(CompanionStatus.sleeping));
        if (index < 2) {
          expect(analysis.status, isNot(CompanionStatus.distracted));
        } else {
          expect(analysis.status, CompanionStatus.distracted);
        }
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
        expect(analysis.status, isNot(CompanionStatus.sleeping));
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
        expect(analysis.status, isNot(CompanionStatus.sleeping));
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
      expect(collapsed.status, CompanionStatus.sleeping);
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

      expect(statuses.sublist(0, 4), everyElement(CompanionStatus.sleeping));
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

      expect(latched.status, CompanionStatus.sleeping);
      expect(recovered.postureDownResult.shoulderDropScore, greaterThan(90));
      expect(recovered.status, CompanionStatus.normal);
    });
  });
}

VisionResult _visionResult({
  int poseSequence = 1,
  double headOffsetScore = 0,
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
    leftEyeOpen: leftEyeOpen,
    rightEyeOpen: rightEyeOpen,
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

VisionResult _readingHeadDownResult({required int poseSequence}) {
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
    poseNoseY: 580,
    poseNoseVisibility: 0.95,
    poseLeftEyeVisibility: 0.95,
    poseRightEyeVisibility: 0.95,
    poseLeftEarVisibility: 0.95,
    poseRightEarVisibility: 0.95,
    leftEyeOpen: 0.8,
    rightEyeOpen: 0.8,
    headYaw: 0,
    headPitch: 18,
    headOffsetScore: 0,
    shoulderWidth: 400,
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
