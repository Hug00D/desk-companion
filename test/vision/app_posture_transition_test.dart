import 'package:desk_companion/companion/companion_controller.dart';
import 'package:desk_companion/companion/return_to_seat_guard.dart';
import 'package:desk_companion/vision/companion_state_evaluator.dart';
import 'package:desk_companion/vision/posture_down_detector.dart';
import 'package:desk_companion/vision/vision_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026, 10, 20, 10);

  PostureDownDetector detector() => PostureDownDetector(
    minimumEvidenceDuration: CompanionController.appPostureConfirmationDuration,
    missingEvidenceGraceDuration:
        CompanionController.appMissingEvidenceGraceDuration,
  );

  void calibrate(PostureDownDetector detector) {
    for (var i = 0; i < 6; i++) {
      detector.evaluate(
        result: frame(sequence: i + 1),
        shouldUpdate: true,
        observedAt: start.add(Duration(milliseconds: 600 * i)),
      );
    }
  }

  group('native hip fields', () {
    test('cold return requires hidden hips plus five stable upright poses', () {
      final guard = ReturnToSeatGuard()..beginReturn();
      for (var i = 0; i < 6; i++) {
        expect(
          guard.suppressPosture(
            frame(sequence: i + 1, standing: true),
            freshPose: true,
            now: start.add(Duration(milliseconds: 600 * i)),
          ),
          isTrue,
        );
      }
      for (var i = 0; i < 5; i++) {
        expect(
          guard.suppressPosture(
            frame(sequence: i + 7),
            freshPose: true,
            now: start.add(Duration(milliseconds: 3600 + 600 * i)),
          ),
          i < 4,
        );
      }
      expect(guard.phase, ReturnToSeatPhase.inactive);
    });

    test('cold return cannot establish a baseline from missing hip fields', () {
      final guard = ReturnToSeatGuard()..beginReturn();
      for (var i = 0; i < 8; i++) {
        expect(
          guard.suppressPosture(
            frame(sequence: i + 1, includeHipData: false),
            freshPose: true,
            now: start.add(Duration(milliseconds: 600 * i)),
          ),
          isTrue,
        );
      }
      expect(guard.isAwaitingReturn, isTrue);
    });
    test(
      'hip coordinates and visibility are parsed from the existing channel map',
      () {
        final result = frame(sequence: 1, standing: true);
        expect(result.leftHipX, 420);
        expect(result.leftHipY, 800);
        expect(result.leftHipVisibility, 0.9);
        expect(result.rightHipX, 580);
        expect(result.rightHipY, 800);
        expect(result.rightHipVisibility, 0.9);
      },
    );

    test('legacy payload leaves hip fields null, not fabricated visible', () {
      final result = frame(sequence: 1, includeHipData: false);
      expect(result.leftHipX, isNull);
      expect(result.leftHipY, isNull);
      expect(result.leftHipVisibility, isNull);
      expect(result.rightHipX, isNull);
      expect(result.rightHipY, isNull);
      expect(result.rightHipVisibility, isNull);
    });
  });

  group('app posture duration', () {
    test('front departure shoulder shrink is not prone evidence', () {
      final d = detector();
      calibrate(d);

      PostureDownDetectionResult? last;
      for (var i = 0; i < 5; i++) {
        last = d.evaluate(
          result: departureFrame(
            sequence: 7 + i,
            shoulderHalfWidth: 180 - i * 25,
            shoulderCenterX: 500,
            shoulderY: 500 + i * 8,
            noseY: 250 + i * 8,
          ),
          shouldUpdate: true,
          observedAt: start.add(Duration(milliseconds: 3600 + 600 * i)),
        );
        expect(last.state, isNot(PostureDownState.down));
      }
      expect(last!.shoulderShrinkScore, greaterThan(45));
      expect(last.downFrameCount, 0);
    });

    test('side departure shoulder shrink is not prone evidence', () {
      final d = detector();
      calibrate(d);

      PostureDownDetectionResult? last;
      for (var i = 0; i < 5; i++) {
        last = d.evaluate(
          result: departureFrame(
            sequence: 7 + i,
            shoulderHalfWidth: 180 - i * 25,
            shoulderCenterX: 500 + i * 45,
            shoulderY: 500 + i * 8,
            noseY: 250 + i * 8,
          ),
          shouldUpdate: true,
          observedAt: start.add(Duration(milliseconds: 3600 + 600 * i)),
        );
        expect(last.state, isNot(PostureDownState.down));
      }
      expect(last!.shoulderShrinkScore, greaterThan(45));
      expect(last.downFrameCount, 0);
    });

    test('candidate grace does not erase already confirmed prone hold', () {
      final d = detector();
      calibrate(d);
      for (var i = 0; i < 3; i++) {
        d.evaluate(
          result: frame(sequence: 7 + i, prone: true),
          shouldUpdate: true,
          observedAt: start.add(Duration(milliseconds: 3600 + 600 * i)),
        );
      }
      for (var i = 0; i < 5; i++) {
        final held = d.evaluate(
          result: frame(sequence: 10 + i, absent: true),
          shouldUpdate: true,
          observedAt: start.add(Duration(milliseconds: 5400 + 600 * i)),
        );
        expect(held.state, PostureDownState.down);
      }
      expect(d.pendingEvidenceDuration, Duration.zero);
    });
    test('short missing-pose gap preserves progress but never adds time', () {
      final d = detector();
      calibrate(d);
      for (var i = 0; i < 2; i++) {
        d.evaluate(
          result: frame(sequence: 7 + i, prone: true),
          shouldUpdate: true,
          observedAt: start.add(Duration(milliseconds: 3600 + 600 * i)),
        );
      }
      expect(d.pendingEvidenceDuration, const Duration(milliseconds: 600));
      d.evaluate(
        result: frame(sequence: 9, absent: true),
        shouldUpdate: true,
        observedAt: start.add(const Duration(milliseconds: 4800)),
      );
      expect(d.pendingEvidenceDuration, const Duration(milliseconds: 600));
      expect(d.isPendingEvidencePaused, isTrue);
      final resumed = d.evaluate(
        result: frame(sequence: 10, prone: true),
        shouldUpdate: true,
        observedAt: start.add(const Duration(milliseconds: 5400)),
      );
      expect(resumed.state, PostureDownState.normal);
      expect(d.pendingEvidenceDuration, const Duration(milliseconds: 600));
      final confirmed = d.evaluate(
        result: frame(sequence: 11, prone: true),
        shouldUpdate: true,
        observedAt: start.add(const Duration(milliseconds: 6000)),
      );
      expect(confirmed.state, PostureDownState.down);
      expect(d.pendingEvidenceDuration, const Duration(milliseconds: 1200));
    });

    test(
      'unreliable pose pauses without changing filters or adding evidence',
      () {
        final d = detector();
        calibrate(d);
        d.evaluate(
          result: frame(sequence: 7, prone: true),
          shouldUpdate: true,
          observedAt: start.add(const Duration(milliseconds: 3600)),
        );
        d.evaluate(
          result: frame(sequence: 8, prone: true),
          shouldUpdate: true,
          observedAt: start.add(const Duration(milliseconds: 4200)),
        );
        d.evaluate(
          result: frame(sequence: 9, prone: true, visibility: 0.4),
          shouldUpdate: true,
          observedAt: start.add(const Duration(milliseconds: 4800)),
        );
        expect(d.isPendingEvidencePaused, isTrue);
        expect(d.pendingEvidenceDuration, const Duration(milliseconds: 600));
        final resumed = d.evaluate(
          result: frame(sequence: 10, prone: true),
          shouldUpdate: true,
          observedAt: start.add(const Duration(milliseconds: 5400)),
        );
        expect(resumed.state, PostureDownState.normal);
        expect(d.pendingEvidenceDuration, const Duration(milliseconds: 600));
      },
    );

    test('repeated missing samples cannot extend grace indefinitely', () {
      final d = detector();
      calibrate(d);
      d.evaluate(
        result: frame(sequence: 7, prone: true),
        shouldUpdate: true,
        observedAt: start.add(const Duration(milliseconds: 3600)),
      );
      d.evaluate(
        result: frame(sequence: 8, prone: true),
        shouldUpdate: true,
        observedAt: start.add(const Duration(milliseconds: 4200)),
      );
      for (var i = 0; i < 4; i++) {
        d.evaluate(
          result: frame(sequence: 9 + i, absent: true),
          shouldUpdate: true,
          observedAt: start.add(Duration(milliseconds: 4800 + 600 * i)),
        );
      }
      expect(d.pendingEvidenceDuration, Duration.zero);
      expect(d.isPendingEvidencePaused, isFalse);
      final returned = d.evaluate(
        result: frame(sequence: 13, prone: true),
        shouldUpdate: true,
        observedAt: start.add(const Duration(milliseconds: 7200)),
      );
      expect(returned.state, isNot(PostureDownState.down));
    });

    test(
      'exact grace boundary preserves progress without counting the gap',
      () {
        final d = detector();
        calibrate(d);
        d.evaluate(
          result: frame(sequence: 7, prone: true),
          shouldUpdate: true,
          observedAt: start.add(const Duration(milliseconds: 3600)),
        );
        d.evaluate(
          result: frame(sequence: 8, prone: true),
          shouldUpdate: true,
          observedAt: start.add(const Duration(milliseconds: 4200)),
        );
        d.evaluate(
          result: frame(sequence: 9, absent: true),
          shouldUpdate: true,
          observedAt: start.add(const Duration(milliseconds: 4800)),
        );
        final returned = d.evaluate(
          result: frame(sequence: 10, prone: true),
          shouldUpdate: true,
          observedAt: start.add(const Duration(milliseconds: 6300)),
        );
        expect(returned.state, PostureDownState.normal);
        expect(d.pendingEvidenceDuration, const Duration(milliseconds: 600));
      },
    );

    test('explicit upright recovery clears pending evidence immediately', () {
      final d = detector();
      calibrate(d);
      d.evaluate(
        result: frame(sequence: 7, prone: true),
        shouldUpdate: true,
        observedAt: start.add(const Duration(milliseconds: 3600)),
      );
      d.evaluate(
        result: frame(sequence: 8, prone: true),
        shouldUpdate: true,
        observedAt: start.add(const Duration(milliseconds: 4200)),
      );
      d.evaluate(
        result: frame(sequence: 9),
        shouldUpdate: true,
        observedAt: start.add(const Duration(milliseconds: 4800)),
      );
      expect(d.pendingEvidenceDuration, Duration.zero);
      expect(d.isPendingEvidencePaused, isFalse);
    });

    test('no fresh pose cannot keep a pending candidate alive forever', () {
      final d = detector();
      calibrate(d);
      final input = frame(sequence: 7, prone: true);
      d.evaluate(
        result: input,
        shouldUpdate: true,
        observedAt: start.add(const Duration(milliseconds: 3600)),
      );
      final stale = d.evaluate(
        result: input,
        shouldUpdate: false,
        observedAt: start.add(const Duration(milliseconds: 5200)),
      );
      expect(stale.state, PostureDownState.normal);
      expect(stale.downFrameCount, 0);
      expect(d.pendingEvidenceDuration, Duration.zero);
    });

    test('two rapid positive poses stay pending instead of flashing down', () {
      final timed = detector();
      final legacy = PostureDownDetector();
      calibrate(timed);
      calibrate(legacy);
      for (final d in [timed, legacy]) {
        d.evaluate(
          result: frame(sequence: 7, prone: true),
          shouldUpdate: true,
          observedAt: start.add(const Duration(milliseconds: 3600)),
        );
      }
      final input = frame(sequence: 8, prone: true);
      final timestamp = start.add(const Duration(milliseconds: 3900));
      expect(
        legacy
            .evaluate(result: input, shouldUpdate: true, observedAt: timestamp)
            .state,
        PostureDownState.down,
      );
      final pending = timed.evaluate(
        result: input,
        shouldUpdate: true,
        observedAt: timestamp,
      );
      expect(pending.downFrameCount, greaterThanOrEqualTo(2));
      expect(pending.state, PostureDownState.normal);
    });

    test('sustained fresh prone poses confirm after 1200ms', () {
      final d = detector();
      calibrate(d);
      for (var i = 0; i < 3; i++) {
        final result = d.evaluate(
          result: frame(sequence: i + 7, prone: true),
          shouldUpdate: true,
          observedAt: start.add(Duration(milliseconds: 3600 + 600 * i)),
        );
        expect(
          result.state,
          i < 2 ? PostureDownState.normal : PostureDownState.down,
        );
      }
    });

    test('reusing a pose or waiting without new poses cannot confirm', () {
      final d = detector();
      calibrate(d);
      final input = frame(sequence: 7, prone: true);
      d.evaluate(
        result: input,
        shouldUpdate: true,
        observedAt: start.add(const Duration(milliseconds: 3600)),
      );
      final stale = d.evaluate(
        result: input,
        shouldUpdate: false,
        observedAt: start.add(const Duration(milliseconds: 5000)),
      );
      expect(stale.state, PostureDownState.normal);
      expect(stale.downFrameCount, 1);
    });

    test('missing pose breaks pending duration instead of confirming it', () {
      final d = detector();
      calibrate(d);
      d.evaluate(
        result: frame(sequence: 7, prone: true),
        shouldUpdate: true,
        observedAt: start.add(const Duration(milliseconds: 3600)),
      );
      d.evaluate(
        result: frame(sequence: 8, absent: true),
        shouldUpdate: true,
        observedAt: start.add(const Duration(milliseconds: 4200)),
      );
      final result = d.evaluate(
        result: frame(sequence: 9, prone: true),
        shouldUpdate: true,
        observedAt: start.add(const Duration(milliseconds: 4800)),
      );
      expect(result.state, PostureDownState.normal);
    });

    test('a large sample gap cannot finish a pending confirmation', () {
      final d = detector();
      calibrate(d);
      d.evaluate(
        result: frame(sequence: 7, prone: true),
        shouldUpdate: true,
        observedAt: start.add(const Duration(milliseconds: 3600)),
      );
      final result = d.evaluate(
        result: frame(sequence: 8, prone: true),
        shouldUpdate: true,
        observedAt: start.add(const Duration(milliseconds: 5200)),
      );
      expect(result.state, PostureDownState.normal);
    });

    test('unreliable landmarks cannot finish timed confirmation', () {
      final d = detector();
      calibrate(d);
      d.evaluate(
        result: frame(sequence: 7, prone: true),
        shouldUpdate: true,
        observedAt: start.add(const Duration(milliseconds: 3600)),
      );
      for (var i = 0; i < 3; i++) {
        final result = d.evaluate(
          result: frame(sequence: i + 8, prone: true, visibility: 0.4),
          shouldUpdate: true,
          observedAt: start.add(Duration(milliseconds: 4200 + 600 * i)),
        );
        expect(result.state, isNot(PostureDownState.down));
      }
    });

    test(
      'clearing tracking keeps the seated baseline but discards descent',
      () {
        final d = detector();
        calibrate(d);
        d.evaluate(
          result: frame(sequence: 7, prone: true),
          shouldUpdate: true,
          observedAt: start.add(const Duration(milliseconds: 3600)),
        );
        d.resetTracking();
        final first = d.evaluate(
          result: frame(sequence: 8, prone: true),
          shouldUpdate: true,
          observedAt: start.add(const Duration(milliseconds: 4200)),
        );
        expect(first.isCalibrating, isFalse);
        expect(first.downFrameCount, 0);
        expect(first.state, PostureDownState.normal);
        d.reset();
        final recalibrating = d.evaluate(
          result: frame(sequence: 9),
          shouldUpdate: true,
          observedAt: start.add(const Duration(milliseconds: 4800)),
        );
        expect(recalibrating.isCalibrating, isTrue);
      },
    );
  });

  group('formal app return-to-seat', () {
    late CompanionController controller;
    late int sequence;
    late int milliseconds;

    CompanionAnalysis step({
      bool prone = false,
      bool absent = false,
      bool standing = false,
      bool? hipsVisible,
      bool includeHipData = true,
      Map<String, Object?>? nativeOverrides,
      int gap = 600,
    }) {
      milliseconds += gap;
      final input = frame(
        sequence: ++sequence,
        prone: prone,
        absent: absent,
        standing: standing,
        hipsVisible: hipsVisible,
        includeHipData: includeHipData,
      );
      return controller.analyze(
        nativeOverrides == null
            ? input
            : VisionResult.fromNativeMap({...input.raw, ...nativeOverrides}),
        observedAt: start.add(Duration(milliseconds: milliseconds)),
      );
    }

    void leave() {
      // Give the departure arbiter enough visible history to confirm away.
      step(gap: 300);
      CompanionAnalysis? last;
      for (var i = 0; i < 10; i++) {
        last = step(absent: true, gap: i == 0 ? 300 : 600);
      }
      expect(last!.status, CompanionStatus.userMissing);
    }

    setUp(() {
      controller = CompanionController(enableDualTrackPilot: true);
      sequence = 0;
      milliseconds = 0;
      for (var i = 0; i < 6; i++) {
        step();
      }
    });

    test(
      'brief prone candidate does not escape through dual-track priority',
      () {
        expect(
          step(prone: true, gap: 300).cause,
          isNot(CompanionCause.postureDown),
        );
        expect(
          step(prone: true, gap: 300).cause,
          isNot(CompanionCause.postureDown),
        );
        for (var i = 0; i < 4; i++) {
          expect(step().cause, isNot(CompanionCause.postureDown));
        }
      },
    );

    test(
      'sustained real prone posture still produces sleeping/postureDown',
      () {
        step(prone: true);
        step(prone: true);
        final confirmed = step(prone: true);
        expect(confirmed.status, CompanionStatus.sleeping);
        expect(confirmed.cause, CompanionCause.postureDown);
      },
    );

    test(
      'person mask plus visible descent preserves prone through landmark loss',
      () {
        step(gap: 300);
        step(
          nativeOverrides: const {'poseNoseY': 550.0, 'headPitch': 30.0},
          gap: 300,
        );
        CompanionAnalysis? result;
        for (var i = 0; i < 10; i++) {
          result = step(
            absent: true,
            nativeOverrides: const {
              'personPresenceSampled': true,
              'personPresent': true,
              'personMaskAreaRatio': 0.7,
            },
          );
        }

        expect(result!.status, CompanionStatus.sleeping);
        expect(result.cause, CompanionCause.postureDown);
        expect(
          controller.lastDualTrackResult?.shortTrigger,
          'presence_confirmed_prone',
        );
      },
    );

    test('confirmed absence overrides a stale posture-down hold', () {
      step(prone: true);
      step(prone: true);
      expect(step(prone: true).cause, CompanionCause.postureDown);

      CompanionAnalysis? result;
      for (var i = 0; i < 3; i++) {
        result = step(absent: true);
      }

      expect(result!.status, CompanionStatus.userMissing);
      expect(result.cause, CompanionCause.userAway);
    });

    test('sitting down after confirmed absence does not become prone', () {
      leave();
      final returning = [
        step(standing: true),
        step(prone: true),
        step(prone: true),
        step(),
        step(),
        step(),
      ];
      expect(
        returning.map((a) => a.status),
        everyElement(isNot(CompanionStatus.sleeping)),
      );
      expect(returning.last.postureDownResult.isCalibrating, isFalse);
      expect(returning.last.status, CompanionStatus.normal);
    });

    test(
      'visible hips block return even when head is already near seated height',
      () {
        leave();
        for (var i = 0; i < 12; i++) {
          final standing = step(hipsVisible: true);
          expect(standing.cause, isNot(CompanionCause.postureDown));
          expect(
            controller.returnToSeatGuard.phase,
            ReturnToSeatPhase.standing,
          );
        }
        step(prone: true, hipsVisible: true);
        step(prone: true, hipsVisible: true);
        expect(
          step(prone: true, hipsVisible: true).cause,
          isNot(CompanionCause.postureDown),
        );
      },
    );

    test('head above seated baseline cannot unlock by elapsed time alone', () {
      leave();
      for (var i = 0; i < 12; i++) {
        step(standing: true, hipsVisible: false);
        expect(controller.returnToSeatGuard.isAwaitingReturn, isTrue);
      }
    });

    test('hip disappearance alone does not unlock while sitting down', () {
      leave();
      step(standing: true);
      for (var i = 0; i < 6; i++) {
        expect(
          step(prone: true, hipsVisible: false).cause,
          isNot(CompanionCause.postureDown),
        );
        expect(controller.returnToSeatGuard.isAwaitingReturn, isTrue);
      }
      for (var i = 0; i < 4; i++) {
        step();
      }
      expect(controller.returnToSeatGuard.phase, ReturnToSeatPhase.inactive);
      expect(controller.lastAnalysis!.postureDownResult.downFrameCount, 0);
    });

    test(
      'missing hip fields do not prove previously visible hips are hidden',
      () {
        leave();
        step(standing: true);
        for (var i = 0; i < 6; i++) {
          step(includeHipData: false);
          expect(controller.returnToSeatGuard.isAwaitingReturn, isTrue);
        }
        for (var i = 0; i < 4; i++) {
          step();
        }
        expect(controller.returnToSeatGuard.phase, ReturnToSeatPhase.inactive);
      },
    );

    test('stale poses cannot satisfy stable seated recovery', () {
      leave();
      step();
      for (var i = 0; i < 6; i++) {
        milliseconds += 600;
        controller.analyze(
          frame(sequence: sequence),
          observedAt: start.add(Duration(milliseconds: milliseconds)),
        );
      }
      expect(controller.returnToSeatGuard.isAwaitingReturn, isTrue);
      for (var i = 0; i < 4; i++) {
        step();
      }
      expect(controller.returnToSeatGuard.phase, ReturnToSeatPhase.inactive);
    });

    test(
      'reliable seated Pose can recover even when Face is temporarily lost',
      () {
        leave();
        step(standing: true);
        for (var i = 0; i < 4; i++) {
          step(nativeOverrides: {'hasFace': false});
        }
        expect(controller.returnToSeatGuard.phase, ReturnToSeatPhase.inactive);
      },
    );

    test('one reliable visible hip is sufficient to retain standing guard', () {
      leave();
      for (var i = 0; i < 6; i++) {
        step(
          nativeOverrides: {
            'poseLeftHipX': 420.0,
            'poseLeftHipY': 800.0,
            'poseLeftHipVisibility': 0.9,
            'poseRightHipX': null,
            'poseRightHipY': null,
            'poseRightHipVisibility': null,
          },
        );
        expect(controller.returnToSeatGuard.phase, ReturnToSeatPhase.standing);
      }
    });

    test(
      'high hip visibility outside the image is not a standing observation',
      () {
        leave();
        for (var i = 0; i < 4; i++) {
          step(
            nativeOverrides: {
              'poseLeftHipVisibility': 0.9,
              'poseRightHipVisibility': 0.9,
            },
          );
        }
        expect(controller.returnToSeatGuard.phase, ReturnToSeatPhase.inactive);
      },
    );

    test('nonfinite hip coordinates cannot prove standing has ended', () {
      leave();
      step(standing: true);
      for (var i = 0; i < 6; i++) {
        step(
          nativeOverrides: {
            'poseLeftHipX': double.nan,
            'poseRightHipY': double.infinity,
          },
        );
      }
      expect(controller.returnToSeatGuard.isAwaitingReturn, isTrue);
    });

    test(
      'a long pose gap restarts stable seating rather than approving it',
      () {
        leave();
        step();
        step(gap: 1600);
        expect(controller.returnToSeatGuard.isAwaitingReturn, isTrue);
        step();
        expect(controller.returnToSeatGuard.isAwaitingReturn, isTrue);
        step();
        expect(controller.returnToSeatGuard.isAwaitingReturn, isTrue);
        step();
        expect(controller.returnToSeatGuard.phase, ReturnToSeatPhase.inactive);
      },
    );

    test('hips do not change normal seated posture logic outside return', () {
      for (var i = 0; i < 4; i++) {
        step(hipsVisible: true);
      }
      expect(controller.returnToSeatGuard.phase, ReturnToSeatPhase.inactive);
      step(prone: true, hipsVisible: true);
      step(prone: true, hipsVisible: true);
      expect(
        step(prone: true, hipsVisible: true).cause,
        CompanionCause.postureDown,
      );
    });

    test(
      'legacy payload without hip fields can recover from stable seated baseline',
      () {
        leave();
        for (var i = 0; i < 4; i++) {
          step(includeHipData: false);
        }
        expect(controller.returnToSeatGuard.phase, ReturnToSeatPhase.inactive);
      },
    );

    test(
      'real prone movement after return settling is not permanently blocked',
      () {
        leave();
        for (var i = 0; i < 6; i++) {
          step();
        }
        step(prone: true);
        step(prone: true);
        final confirmed = step(prone: true);
        expect(confirmed.status, CompanionStatus.sleeping);
        expect(confirmed.cause, CompanionCause.postureDown);
      },
    );

    test('a return interrupted by another absence restarts settling', () {
      leave();
      step(standing: true);
      step(absent: true);
      expect(step(prone: true).cause, isNot(CompanionCause.postureDown));
      expect(step(prone: true).cause, isNot(CompanionCause.postureDown));
      expect(step(prone: true).cause, isNot(CompanionCause.postureDown));
    });

    test('stale camera samples cannot consume the return settling window', () {
      leave();
      step(standing: true);
      expect(
        step(prone: true, gap: 2000).cause,
        isNot(CompanionCause.postureDown),
      );
      expect(step(prone: true).cause, isNot(CompanionCause.postureDown));
      expect(step(prone: true).cause, isNot(CompanionCause.postureDown));
    });

    test('weak empty-chair poses cannot spend the return settling window', () {
      leave();
      for (var i = 0; i < 5; i++) {
        milliseconds += 600;
        final weak = controller.analyze(
          frame(sequence: ++sequence, prone: true, visibility: 0.4),
          observedAt: start.add(Duration(milliseconds: milliseconds)),
        );
        expect(weak.cause, isNot(CompanionCause.postureDown));
      }
      expect(step(standing: true).cause, isNot(CompanionCause.postureDown));
      expect(step(prone: true).cause, isNot(CompanionCause.postureDown));
      expect(step(prone: true).cause, isNot(CompanionCause.postureDown));
    });

    test(
      'short face loss without confirmed absence does not start settling',
      () {
        step(absent: true);
        step();
        step(prone: true);
        step(prone: true);
        expect(step(prone: true).cause, CompanionCause.postureDown);
      },
    );

    test('reset clears the pending return episode', () {
      leave();
      controller.reset();
      for (var i = 0; i < 6; i++) {
        step();
      }
      step(prone: true);
      step(prone: true);
      expect(step(prone: true).cause, CompanionCause.postureDown);
    });
  });
}

VisionResult frame({
  required int sequence,
  bool prone = false,
  bool absent = false,
  bool standing = false,
  bool? hipsVisible,
  bool includeHipData = true,
  double visibility = 0.9,
}) {
  if (absent) {
    return VisionResult.fromNativeMap({
      'poseSequence': sequence,
      'hasFace': false,
      'hasPose': false,
      'personPresenceSampled': true,
      'personPresent': false,
    });
  }
  final shoulderY = standing
      ? 350.0
      : prone
      ? 600.0
      : 500.0;
  final noseY = standing
      ? 100.0
      : prone
      ? 580.0
      : 250.0;
  final halfWidth = prone ? 125.0 : 200.0;
  final showHips = hipsVisible ?? standing;
  return VisionResult.fromNativeMap({
    'poseSequence': sequence,
    'hasFace': !prone,
    'hasPose': true,
    'imageWidth': 1000.0,
    'imageHeight': 1000.0,
    'lsX': 500.0 - halfWidth,
    'lsY': shoulderY,
    'rsX': 500.0 + halfWidth,
    'rsY': shoulderY,
    'lsVisibility': visibility,
    'rsVisibility': visibility,
    'poseNoseX': 500.0,
    'poseNoseY': noseY,
    'poseNoseVisibility': prone ? 0.3 : 0.95,
    'poseLeftEyeVisibility': prone ? 0.2 : 0.95,
    'poseRightEyeVisibility': prone ? 0.2 : 0.95,
    'poseLeftEarVisibility': prone ? 0.3 : 0.95,
    'poseRightEarVisibility': prone ? 0.3 : 0.95,
    'headPitch': 0.0,
    'headOffsetScore': 0.0,
    'leftEye': 0.8,
    'rightEye': 0.8,
    if (includeHipData) ...{
      'poseLeftHipX': 420.0,
      'poseLeftHipY': showHips ? 800.0 : 1200.0,
      'poseLeftHipVisibility': showHips ? 0.9 : 0.1,
      'poseRightHipX': 580.0,
      'poseRightHipY': showHips ? 800.0 : 1200.0,
      'poseRightHipVisibility': showHips ? 0.9 : 0.1,
    },
  });
}

VisionResult departureFrame({
  required int sequence,
  required double shoulderHalfWidth,
  required double shoulderCenterX,
  required double shoulderY,
  required double noseY,
}) {
  return VisionResult.fromNativeMap({
    ...frame(sequence: sequence).raw,
    'hasFace': false,
    'lsX': shoulderCenterX - shoulderHalfWidth,
    'lsY': shoulderY,
    'rsX': shoulderCenterX + shoulderHalfWidth,
    'rsY': shoulderY,
    'poseNoseX': shoulderCenterX,
    'poseNoseY': noseY,
    'poseNoseVisibility': 0.75,
    'poseLeftEyeVisibility': 0.45,
    'poseRightEyeVisibility': 0.45,
    'poseLeftEarVisibility': 0.5,
    'poseRightEarVisibility': 0.5,
  });
}
