import 'dart:io';

import 'package:desk_companion/vision/companion_state_evaluator.dart';
import 'package:desk_companion/vision/disappearance_context_classifier.dart';
import 'package:desk_companion/vision/dual_track_context_classifier.dart';
import 'package:desk_companion/vision/dual_track_lab_report.dart';
import 'package:desk_companion/vision/vision_lab_comparison.dart';
import 'package:desk_companion/vision/vision_lab_replay.dart';
import 'package:desk_companion/vision/vision_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/vision_lab_dual_track.dart' as cli;
import '../../tool/vision_lab_replay_companion.dart' as original_replay;

const _fixture = 'test/fixtures/vision/dual_track_features.csv';
const _truth = 'test/fixtures/vision/dual_track_truth.csv';
const _baseline = 'test/fixtures/vision/dual_track_replay_baseline.csv';

String normalizeNewlines(String value) => value.replaceAll('\r\n', '\n');

DualTrackContextResult sample(
  DualTrackContextClassifier classifier,
  int ms, {
  double pitch = 0,
  double drop = 0,
  bool closed = false,
  bool face = true,
  bool pose = true,
  double visibility = 1,
  bool eyeData = true,
  double? eyeOpen,
  CompanionStatus fastStatus = CompanionStatus.normal,
  CompanionCause fastCause = CompanionCause.none,
  bool strongPosture = false,
  double? postureScore,
  bool? personPresent,
}) => classifier.classify(
  timestampMs: ms,
  result: VisionResult.fromNativeMap({
    'hasFace': face,
    'hasPose': pose,
    'imageWidth': 640.0,
    'imageHeight': 640.0,
    'poseNoseX': 320.0,
    'poseNoseY': 220.0 + drop * 640,
    'poseNoseVisibility': visibility,
    'lsX': 220.0,
    'lsY': 350.0,
    'lsVisibility': visibility,
    'rsX': 420.0,
    'rsY': 350.0,
    'rsVisibility': visibility,
    'headPitch': pitch,
    'headYaw': 0.0,
    'headOffsetScore': 0.0,
    if (eyeData) 'leftEye': eyeOpen ?? (closed ? 0.03 : 0.8),
    if (eyeData) 'rightEye': eyeOpen ?? (closed ? 0.03 : 0.8),
    'personPresenceSampled': personPresent != null,
    'personPresent': personPresent,
    'personMaskAreaRatio': personPresent == null
        ? null
        : personPresent
        ? 0.7
        : 0.0,
  }),
  fastState: CompanionState(status: fastStatus, cause: fastCause),
  rawEyeClosed: closed,
  strongPostureEvidence: strongPosture,
  postureScore: postureScore,
);

void warm(DualTrackContextClassifier classifier) {
  for (final ms in [0, 100, 250, 500]) {
    sample(classifier, ms);
  }
}

DualTrackContextResult lowUntil(
  DualTrackContextClassifier classifier,
  int endMs, {
  bool closed = false,
  bool face = true,
  double visibility = 1,
}) {
  for (var ms = 1000; ms < endMs; ms += 250) {
    sample(
      classifier,
      ms,
      pitch: 30,
      drop: 0.08,
      closed: closed,
      face: face,
      visibility: visibility,
    );
  }
  return sample(
    classifier,
    endMs,
    pitch: 30,
    drop: 0.08,
    closed: closed,
    face: face,
    visibility: visibility,
  );
}

void main() {
  test('1999 ms does not complete a 2000 ms window', () {
    final classifier = DualTrackContextClassifier();
    warm(classifier);
    final before = lowUntil(classifier, 2999);
    expect(before.slowState, SlowContextState.none);
    expect(before.slowWindowMs, 1999);
    final at = sample(classifier, 3000, pitch: 30, drop: 0.08);
    expect(at.slowWindowMs, 2000);
    expect(at.slowState, SlowContextState.readingLike);
  });

  test('irregular PTS uses milliseconds, not number of observations', () {
    final classifier = DualTrackContextClassifier(windowMs: 3000);
    warm(classifier);
    for (final ms in [
      1000,
      1111,
      1510,
      1800,
      2110,
      2500,
      2990,
      3400,
      3800,
      3999,
    ]) {
      final result = sample(classifier, ms, pitch: 30, drop: 0.08);
      expect(result.slowState, SlowContextState.none);
    }
    expect(
      sample(classifier, 4000, pitch: 30, drop: 0.08).slowState,
      SlowContextState.readingLike,
    );
  });

  test('formal-app sampling keeps long-track and head-sum history', () {
    final classifier = DualTrackContextClassifier(
      enablePresenceContext: true,
      enableHeadScoreSum: true,
      enableLongShortGate: true,
      maximumSampleGapMs: 1500,
    );
    for (final ms in [0, 600, 1200]) {
      sample(classifier, ms);
    }

    DualTrackContextResult? result;
    for (final ms in [1800, 2400, 3000, 3600, 4200]) {
      result = sample(classifier, ms, pitch: 30, drop: 0.08);
    }

    expect(result?.slowWindowMs, 2000);
    expect(result?.slowState, isNot(SlowContextState.none));
    expect(result?.headScore?.scoreWindowSamples, 5);
  });

  test('short low head does not create a slow event', () {
    final classifier = DualTrackContextClassifier();
    warm(classifier);
    sample(classifier, 700, pitch: 30, drop: 0.08);
    sample(classifier, 950, pitch: 30, drop: 0.08);
    expect(sample(classifier, 1200).slowState, SlowContextState.none);
  });

  test('face loss alone never establishes low-head sleep', () {
    final classifier = DualTrackContextClassifier();
    warm(classifier);
    for (var ms = 750; ms <= 3500; ms += 250) {
      final result = sample(classifier, ms, face: false, closed: true);
      expect(result.slowState, SlowContextState.none);
      expect(result.evidenceEye, isFalse);
      expect(result.finalState, 'normal');
    }
  });

  test('closure alone leaves upright fast fatigue handling intact', () {
    final classifier = DualTrackContextClassifier();
    warm(classifier);
    for (var ms = 750; ms <= 3500; ms += 250) {
      final result = sample(
        classifier,
        ms,
        closed: true,
        fastStatus: CompanionStatus.fatigue,
        fastCause: CompanionCause.eyeClosed,
      );
      expect(result.slowState, SlowContextState.none);
      expect(result.finalState, 'fatigue');
    }
  });

  test('reliable closure followed by descent supplies cross evidence', () {
    final classifier = DualTrackContextClassifier();
    warm(classifier);
    sample(classifier, 600, closed: true);
    sample(classifier, 750, closed: true);
    sample(classifier, 900, closed: true);
    final result = lowUntil(classifier, 3000, closed: true);
    expect(result.evidenceEye, isTrue);
    expect(result.evidenceMotion, isTrue);
    expect(result.evidencePosture, isTrue);
    expect(result.slowState, SlowContextState.drowsyLike);
  });

  test('confirmed cross evidence remains until stable upright recovery', () {
    final classifier = DualTrackContextClassifier();
    warm(classifier);
    for (final ms in [600, 750, 900]) {
      sample(classifier, ms, closed: true);
    }
    lowUntil(classifier, 3000, closed: true);
    for (var ms = 3250; ms <= 6000; ms += 250) {
      final result = sample(
        classifier,
        ms,
        pitch: 30,
        drop: 0.08,
        closed: true,
      );
      expect(result.slowState, SlowContextState.drowsyLike);
      expect(result.evidenceMotion, isTrue);
    }
    sample(classifier, 6250);
    sample(classifier, 6500);
    expect(sample(classifier, 6750).slowState, SlowContextState.none);
  });

  test('stationary low head plus closure has insufficient cross evidence', () {
    final classifier = DualTrackContextClassifier();
    warm(classifier);
    final result = lowUntil(classifier, 3500, closed: true);
    expect(result.evidenceEye, isTrue);
    expect(result.evidenceMotion, isFalse);
    expect(result.slowState, SlowContextState.unknownLowHead);
  });

  test(
    'unreliable pose and missing eyes cannot count as positive evidence',
    () {
      for (final visibility in [0.49, double.nan]) {
        final classifier = DualTrackContextClassifier();
        warm(classifier);
        final result = lowUntil(
          classifier,
          3000,
          closed: true,
          visibility: visibility,
        );
        expect(result.evidencePosture, isFalse);
        expect(result.slowState, SlowContextState.unknownLowHead);
      }
      final classifier = DualTrackContextClassifier();
      warm(classifier);
      for (var ms = 1000; ms <= 3500; ms += 250) {
        final result = sample(
          classifier,
          ms,
          pitch: 30,
          drop: 0.08,
          closed: true,
          eyeData: false,
        );
        expect(result.evidenceEye, isFalse);
        expect(result.slowState, isNot(SlowContextState.drowsyLike));
      }
    },
  );

  test(
    'usable pitch with missing eyes and pose remains an uncertain low head',
    () {
      final classifier = DualTrackContextClassifier();
      warm(classifier);
      for (var ms = 1000; ms <= 3000; ms += 250) {
        sample(classifier, ms, pitch: 30, pose: false, eyeData: false);
      }
      final result = sample(
        classifier,
        3250,
        pitch: 30,
        pose: false,
        eyeData: false,
      );
      expect(result.lowHeadCandidate, isTrue);
      expect(result.evidenceEye, isFalse);
      expect(result.evidencePosture, isFalse);
      expect(result.slowState, SlowContextState.unknownLowHead);
    },
  );

  test('low openness without raw closure stays uncertain', () {
    final classifier = DualTrackContextClassifier();
    warm(classifier);
    for (var ms = 1000; ms <= 3500; ms += 250) {
      sample(classifier, ms, pitch: 30, drop: 0.08, eyeOpen: 0.03);
    }
    expect(
      sample(classifier, 3750, pitch: 30, drop: 0.08, eyeOpen: 0.03).slowState,
      SlowContextState.unknownLowHead,
    );
  });

  test('stable upright recovery releases the episode at 500 ms', () {
    final classifier = DualTrackContextClassifier();
    warm(classifier);
    lowUntil(classifier, 3000);
    expect(sample(classifier, 3250).slowState, SlowContextState.readingLike);
    expect(sample(classifier, 3500).slowState, SlowContextState.readingLike);
    expect(sample(classifier, 3749).slowState, SlowContextState.readingLike);
    expect(sample(classifier, 3750).slowState, SlowContextState.none);
    expect(sample(classifier, 4000).finalState, 'normal');
  });

  test('loss of data during a slow episode becomes uncertainty', () {
    final classifier = DualTrackContextClassifier();
    warm(classifier);
    lowUntil(classifier, 3000);
    final result = sample(
      classifier,
      3250,
      face: false,
      pose: false,
      closed: true,
    );
    expect(result.slowState, SlowContextState.unknownLowHead);
    expect(result.finalState, 'unknown_low_head');
  });

  test('mature low-head tracking loss does not become user missing', () {
    final classifier = DualTrackContextClassifier(
      enablePresenceContext: true,
      enableLongShortGate: true,
    );
    warm(classifier);
    lowUntil(classifier, 3000);
    sample(
      classifier,
      3250,
      face: false,
      pose: false,
      fastStatus: CompanionStatus.userMissing,
      fastCause: CompanionCause.userAway,
    );
    sample(
      classifier,
      3500,
      face: false,
      pose: false,
      fastStatus: CompanionStatus.userMissing,
      fastCause: CompanionCause.userAway,
    );
    final result = sample(
      classifier,
      3750,
      face: false,
      pose: false,
      fastStatus: CompanionStatus.userMissing,
      fastCause: CompanionCause.userAway,
    );
    expect(result.disappearance!.state, DisappearanceState.unknown);
    expect(result.disappearance!.reason, 'low_head_tracking_lost');
    expect(result.finalState, 'unknown_low_head');
  });

  test('person mask blocks a fast user-missing override', () {
    final classifier = DualTrackContextClassifier(
      enablePresenceContext: true,
      enableLongShortGate: true,
    );
    warm(classifier);

    final result = sample(
      classifier,
      750,
      face: false,
      pose: false,
      fastStatus: CompanionStatus.userMissing,
      fastCause: CompanionCause.userAway,
      personPresent: true,
    );

    expect(result.finalState, isNot('user_missing'));
  });

  test('prolonged low-head loss while person remains stays uncertain', () {
    final classifier = DualTrackContextClassifier(
      enablePresenceContext: true,
      enableLongShortGate: true,
    );
    warm(classifier);
    lowUntil(classifier, 3000);

    DualTrackContextResult? result;
    for (var ms = 3250; ms <= 8000; ms += 250) {
      result = sample(
        classifier,
        ms,
        face: false,
        pose: false,
        fastStatus: CompanionStatus.userMissing,
        fastCause: CompanionCause.userAway,
        personPresent: true,
      );
      expect(result.sleepLatched, isFalse);
    }
    result = sample(
      classifier,
      8250,
      face: false,
      pose: false,
      fastStatus: CompanionStatus.userMissing,
      fastCause: CompanionCause.userAway,
      personPresent: true,
    );

    expect(result.disappearance?.reason, 'low_head_tracking_lost');
    expect(result.shortTrigger, 'none');
    expect(result.sleepLatched, isFalse);
    expect(result.finalState, 'unknown_low_head');
    expect(result.continuousTrackingLossMs, 5000);
    expect(result.sleepLatchSource, 'none');
  });

  test(
    'visible descent plus five-second tracked loss confirms prone, not away',
    () {
      final classifier = DualTrackContextClassifier(
        enablePresenceContext: true,
        enableLongShortGate: true,
      );
      warm(classifier);
      sample(classifier, 750);
      sample(classifier, 1000, pitch: 30, drop: 0.08);

      DualTrackContextResult? result;
      for (var ms = 1250; ms < 6250; ms += 250) {
        result = sample(
          classifier,
          ms,
          face: false,
          pose: false,
          fastStatus: CompanionStatus.userMissing,
          fastCause: CompanionCause.userAway,
          personPresent: true,
        );
        expect(result.finalState, isNot('posture_down'));
      }
      result = sample(
        classifier,
        6250,
        face: false,
        pose: false,
        fastStatus: CompanionStatus.userMissing,
        fastCause: CompanionCause.userAway,
        personPresent: true,
      );

      expect(result.disappearance?.state, DisappearanceState.sleepCandidate);
      expect(result.disappearance?.relativeDescent, isTrue);
      expect(result.disappearance?.sideExit, isFalse);
      expect(result.continuousTrackingLossMs, 5000);
      expect(result.shortTrigger, 'presence_confirmed_prone');
      expect(result.finalState, 'posture_down');
    },
  );

  test(
    'sleep-first tracking-loss clock resets when either tracker returns',
    () {
      final classifier = DualTrackContextClassifier(
        enablePresenceContext: true,
        enableLongShortGate: true,
      );
      warm(classifier);
      lowUntil(classifier, 3000);

      for (var ms = 3250; ms <= 7000; ms += 250) {
        expect(
          sample(
            classifier,
            ms,
            face: false,
            pose: false,
            fastStatus: CompanionStatus.userMissing,
            fastCause: CompanionCause.userAway,
            personPresent: true,
          ).sleepLatched,
          isFalse,
        );
      }
      final trackerReturned = sample(
        classifier,
        7250,
        pitch: 30,
        drop: 0.08,
        face: false,
        pose: true,
      );
      expect(trackerReturned.continuousTrackingLossMs, 0);

      for (var ms = 7500; ms < 12500; ms += 250) {
        expect(
          sample(
            classifier,
            ms,
            face: false,
            pose: false,
            fastStatus: CompanionStatus.userMissing,
            fastCause: CompanionCause.userAway,
            personPresent: true,
          ).sleepLatched,
          isFalse,
        );
      }
      final confirmed = sample(
        classifier,
        12500,
        face: false,
        pose: false,
        fastStatus: CompanionStatus.userMissing,
        fastCause: CompanionCause.userAway,
        personPresent: true,
      );
      expect(confirmed.continuousTrackingLossMs, 5000);
      expect(confirmed.sleepLatched, isFalse);
      expect(confirmed.finalState, 'unknown_low_head');
    },
  );

  test('tracking loss without person evidence never confirms sleep', () {
    final classifier = DualTrackContextClassifier(
      enablePresenceContext: true,
      enableLongShortGate: true,
    );
    warm(classifier);
    lowUntil(classifier, 3000);

    DualTrackContextResult? result;
    for (var ms = 3250; ms <= 9000; ms += 250) {
      result = sample(
        classifier,
        ms,
        face: false,
        pose: false,
        fastStatus: CompanionStatus.userMissing,
        fastCause: CompanionCause.userAway,
        personPresent: false,
      );
    }

    expect(result?.sleepLatched, isFalse);
    expect(result?.finalState, isNot('drowsy_like'));
  });

  test(
    'fast missing, strong posture and distraction override slow context',
    () {
      for (final status in [
        CompanionStatus.userMissing,
        CompanionStatus.sleeping,
        CompanionStatus.distracted,
      ]) {
        final classifier = DualTrackContextClassifier();
        warm(classifier);
        lowUntil(classifier, 3000);
        final result = sample(
          classifier,
          3250,
          pitch: 30,
          drop: 0.08,
          fastStatus: status,
          strongPosture: status == CompanionStatus.sleeping,
        );
        expect(result.finalState, switch (status) {
          CompanionStatus.userMissing => 'user_missing',
          CompanionStatus.sleeping => 'posture_down',
          _ => 'distracted',
        });
        expect(result.slowState, SlowContextState.none);
      }
      final classifier = DualTrackContextClassifier();
      warm(classifier);
      final both = sample(
        classifier,
        750,
        fastStatus: CompanionStatus.userMissing,
        strongPosture: true,
      );
      expect(both.finalState, 'user_missing');
    },
  );

  test('long-short gate keeps observing while fast output has priority', () {
    final classifier = DualTrackContextClassifier(enableLongShortGate: true);
    warm(classifier);
    for (var ms = 1000; ms < 3000; ms += 250) {
      sample(
        classifier,
        ms,
        pitch: 30,
        drop: 0.08,
        fastStatus: ms == 2000
            ? CompanionStatus.distracted
            : CompanionStatus.normal,
      );
    }
    final result = sample(classifier, 3000, pitch: 30, drop: 0.08);
    expect(result.slowWindowMs, 2000);
    expect(result.longContext, LongHeadContext.stableLowHead);
    expect(result.slowState, SlowContextState.readingLike);
  });

  test(
    'static deep posture confirms only after 1000 ms and a mature track',
    () {
      final classifier = DualTrackContextClassifier(enableLongShortGate: true);
      warm(classifier);
      for (var ms = 1000; ms < 2000; ms += 250) {
        sample(classifier, ms, pitch: 30, drop: 0.08, postureScore: 79.9);
      }
      for (var ms = 2000; ms < 3000; ms += 250) {
        final result = sample(
          classifier,
          ms,
          pitch: 30,
          drop: 0.08,
          postureScore: 80,
        );
        expect(result.sleepLatched, isFalse);
      }
      final before = sample(
        classifier,
        2999,
        pitch: 30,
        drop: 0.08,
        postureScore: 80,
      );
      expect(before.staticDeepPostureMs, 999);
      expect(before.sleepLatched, isFalse);
      final confirmed = sample(
        classifier,
        3000,
        pitch: 30,
        drop: 0.08,
        postureScore: 80,
      );
      expect(confirmed.staticDeepPostureMs, 1000);
      expect(confirmed.shortTrigger, 'static_deep_posture');
      expect(confirmed.longContext, LongHeadContext.possibleDrowsy);
      expect(confirmed.sleepLatched, isTrue);
      expect(confirmed.finalState, 'drowsy_like');
    },
  );

  test('static deep posture latch releases after the score recovers', () {
    final classifier = DualTrackContextClassifier(enableLongShortGate: true);
    warm(classifier);
    for (var ms = 1000; ms <= 3000; ms += 250) {
      sample(classifier, ms, pitch: 30, drop: 0.08, postureScore: 90);
    }
    expect(
      sample(
        classifier,
        3250,
        pitch: 30,
        drop: 0.08,
        postureScore: 70,
      ).sleepLatched,
      isTrue,
    );
    expect(
      sample(
        classifier,
        3500,
        pitch: 30,
        drop: 0.08,
        postureScore: 70,
      ).sleepLatched,
      isTrue,
    );
    final recovered = sample(
      classifier,
      3750,
      pitch: 30,
      drop: 0.08,
      postureScore: 70,
    );
    expect(recovered.sleepLatched, isFalse);
    expect(recovered.finalState, 'reading_like');
  });

  test('strong posture latches sleep through a short tracking loss', () {
    final classifier = DualTrackContextClassifier(
      enablePresenceContext: true,
      enableLongShortGate: true,
    );
    warm(classifier);
    DualTrackContextResult? trigger;
    for (var ms = 1000; ms <= 3000; ms += 250) {
      trigger = sample(
        classifier,
        ms,
        pitch: 30,
        drop: 0.08,
        fastStatus: CompanionStatus.sleeping,
        fastCause: CompanionCause.postureDown,
        strongPosture: true,
      );
    }
    expect(trigger!.longContext, LongHeadContext.possibleDrowsy);
    expect(trigger.finalState, 'posture_down');
    expect(trigger.sleepLatched, isTrue);
    DualTrackContextResult? missing;
    for (var ms = 3250; ms <= 4750; ms += 250) {
      missing = sample(
        classifier,
        ms,
        face: false,
        pose: false,
        fastStatus: CompanionStatus.userMissing,
        fastCause: CompanionCause.userAway,
      );
    }
    expect(missing!.sleepLatched, isTrue);
    expect(missing.finalState, 'drowsy_like');
    expect(missing.slowState, SlowContextState.drowsyLike);
  });

  test(
    'strong posture plus reliable eye evidence can latch before maturity',
    () {
      final classifier = DualTrackContextClassifier(enableLongShortGate: true);
      warm(classifier);
      DualTrackContextResult? result;
      for (var ms = 1000; ms <= 2000; ms += 250) {
        result = sample(
          classifier,
          ms,
          pitch: 30,
          drop: 0.08,
          closed: true,
          fastStatus: CompanionStatus.sleeping,
          fastCause: CompanionCause.postureDown,
          strongPosture: true,
        );
      }
      expect(result!.slowWindowMs, lessThan(2000));
      expect(result.poseCoverage, greaterThanOrEqualTo(0.8));
      expect(result.evidenceEye, isTrue);
      expect(result.sleepLatched, isTrue);
      expect(result.sleepLatchSource, 'corroborated_strong_posture');
    },
  );

  test('strong posture waits when recent pose history is too sparse', () {
    final classifier = DualTrackContextClassifier(
      enablePresenceContext: true,
      enableLongShortGate: true,
    );
    warm(classifier);
    for (var ms = 1000; ms < 3000; ms += 250) {
      final result = sample(classifier, ms, pitch: 30, pose: false);
      expect(result.sleepLatched, isFalse);
    }
    final trigger = sample(
      classifier,
      3000,
      pitch: 30,
      drop: 0.08,
      fastStatus: CompanionStatus.sleeping,
      fastCause: CompanionCause.postureDown,
      strongPosture: true,
    );
    expect(trigger.poseCoverage, lessThan(0.8));
    expect(trigger.evidencePosture, isFalse);
    expect(trigger.shortTrigger, 'strong_posture');
    expect(trigger.poseCoverage, lessThan(0.4));
    expect(trigger.sleepLatched, isFalse);
    expect(trigger.finalState, 'posture_down');
  });

  test('strong posture still waits for a mature low-head track', () {
    final classifier = DualTrackContextClassifier(
      enablePresenceContext: true,
      enableLongShortGate: true,
    );
    warm(classifier);
    final early = sample(
      classifier,
      1000,
      pitch: 30,
      drop: 0.08,
      fastStatus: CompanionStatus.sleeping,
      fastCause: CompanionCause.postureDown,
      strongPosture: true,
    );
    expect(early.slowWindowMs, 0);
    expect(early.sleepLatched, isFalse);
    expect(early.finalState, 'posture_down');
  });

  test('latched sleep releases only after reliable upright recovery', () {
    final classifier = DualTrackContextClassifier(enableLongShortGate: true);
    warm(classifier);
    for (var ms = 1000; ms <= 3000; ms += 250) {
      sample(
        classifier,
        ms,
        pitch: 30,
        drop: 0.08,
        fastStatus: CompanionStatus.sleeping,
        fastCause: CompanionCause.postureDown,
        strongPosture: true,
      );
    }
    expect(sample(classifier, 3250).sleepLatched, isTrue);
    expect(sample(classifier, 3500).sleepLatched, isTrue);
    final recovered = sample(classifier, 3750);
    expect(recovered.sleepLatched, isFalse);
    expect(recovered.slowState, SlowContextState.none);
    expect(recovered.finalState, 'normal');
  });

  test('latched sleep releases after sustained pose-only head recovery', () {
    final classifier = DualTrackContextClassifier(enableLongShortGate: true);
    warm(classifier);
    for (var ms = 1000; ms <= 3000; ms += 250) {
      sample(
        classifier,
        ms,
        pitch: 30,
        drop: 0.08,
        eyeData: false,
        fastStatus: CompanionStatus.sleeping,
        fastCause: CompanionCause.postureDown,
        strongPosture: true,
      );
    }
    expect(sample(classifier, 3250, eyeData: false).sleepLatched, isTrue);
    expect(sample(classifier, 3500, eyeData: false).sleepLatched, isTrue);
    expect(sample(classifier, 3750, eyeData: false).sleepLatched, isTrue);
    expect(sample(classifier, 4000, eyeData: false).sleepLatched, isTrue);
    final recovered = sample(classifier, 4250, eyeData: false);
    expect(recovered.sleepLatched, isFalse);
    expect(recovered.finalState, 'normal');
  });

  test('reliable low-head tracking releases a stale posture latch', () {
    final classifier = DualTrackContextClassifier(enableLongShortGate: true);
    warm(classifier);
    for (var ms = 1000; ms <= 3000; ms += 250) {
      sample(
        classifier,
        ms,
        pitch: 30,
        drop: 0.08,
        fastStatus: CompanionStatus.sleeping,
        fastCause: CompanionCause.postureDown,
        strongPosture: true,
      );
    }
    expect(
      sample(classifier, 3250, pitch: 30, drop: 0.08).sleepLatched,
      isTrue,
    );
    expect(
      sample(classifier, 3500, pitch: 30, drop: 0.08).sleepLatched,
      isTrue,
    );
    final recovered = sample(classifier, 3750, pitch: 30, drop: 0.08);
    expect(recovered.sleepLatched, isFalse);
    expect(recovered.finalState, 'reading_like');
  });

  test('reliable low-head eye tracking rejects an ambiguous sleep trigger', () {
    final classifier = DualTrackContextClassifier(enableLongShortGate: true);
    warm(classifier);
    DualTrackContextResult? result;
    for (var ms = 1000; ms <= 3000; ms += 250) {
      result = sample(
        classifier,
        ms,
        pitch: 30,
        drop: 0.08,
        closed: true,
        fastStatus: CompanionStatus.sleeping,
        fastCause: CompanionCause.drowsy,
      );
    }
    expect(result!.eyeCoverage, greaterThanOrEqualTo(0.8));
    expect(result.longContext, isNot(LongHeadContext.possibleDrowsy));
    expect(result.sleepLatched, isFalse);
  });

  test('weak low-head sleeping output waits for the slow window', () {
    final classifier = DualTrackContextClassifier();
    warm(classifier);
    expect(
      sample(
        classifier,
        750,
        pitch: 30,
        drop: 0.08,
        fastStatus: CompanionStatus.sleeping,
        fastCause: CompanionCause.drowsy,
      ).finalState,
      'normal',
    );
  });

  test(
    'a timestamp gap restarts observation instead of fabricating duration',
    () {
      final classifier = DualTrackContextClassifier();
      warm(classifier);
      sample(classifier, 750, pitch: 30, drop: 0.08);
      final result = sample(classifier, 5000, pitch: 30, drop: 0.08);
      expect(result.slowState, SlowContextState.none);
      expect(result.slowWindowMs, 0);
      expect(result.evidenceMotion, isFalse);
    },
  );

  test('reset clears calibration, timestamps and all temporal evidence', () {
    final classifier = DualTrackContextClassifier();
    warm(classifier);
    lowUntil(classifier, 3000, closed: true);
    classifier.reset();
    final result = sample(classifier, 0, pitch: 30, drop: 0.08, closed: true);
    expect(result.dataQuality, 'calibrating');
    expect(result.slowState, SlowContextState.none);
    expect(result.evidenceEye, isFalse);
    expect(result.evidenceMotion, isFalse);
    expect(result.noseDrop, isNull);
  });

  test('invalid window or reversed timestamp is rejected', () {
    expect(
      () => DualTrackContextClassifier(windowMs: 2500),
      throwsArgumentError,
    );
    final classifier = DualTrackContextClassifier();
    sample(classifier, 10);
    expect(() => sample(classifier, 10), throwsArgumentError);
    expect(() => sample(classifier, -1), throwsArgumentError);
  });

  test('shared replay matches the baseline frozen before extraction', () async {
    final frames = parseVisionLabReplayFrames(
      await readVisionLabReplayCsv(_fixture),
    );
    final replay = VisionLabCompanionReplay();
    final lines = [
      visionLabReplayHeader,
      for (final frame in frames)
        visionLabReplayRow(frame, replay.evaluate(frame)),
    ];
    expect(
      '${lines.join('\n')}\n',
      normalizeNewlines(await File(_baseline).readAsString()),
    );
    replay.reset();
    expect(
      visionLabReplayRow(frames.first, replay.evaluate(frames.first)),
      lines[1],
    );
  });

  test(
    'original replay CLI output is unchanged after helper extraction',
    () async {
      final directory = await Directory.systemTemp.createTemp('dual_replay_');
      addTearDown(() => directory.delete(recursive: true));
      final output = '${directory.path}/replay.csv';
      await original_replay.main([_fixture, _truth, output]);
      expect(
        normalizeNewlines(await File(output).readAsString()),
        normalizeNewlines(await File(_baseline).readAsString()),
      );
    },
  );

  test(
    'native face loss may omit calibration without inventing eye data',
    () async {
      final rows = await readVisionLabReplayCsv(_fixture);
      final faceIndex = rows.first.indexOf('face_detected');
      final calibrationIndex = rows.first.indexOf('head_offset_calibrating');
      final native = rows.map((row) => List<String>.of(row)).toList();
      for (final row in native.skip(1)) {
        if (row[faceIndex] == 'false') row[calibrationIndex] = '';
      }
      final frames = parseVisionLabReplayFrames(
        native,
        requireRawEyeClosed: true,
      );
      final replay = VisionLabCompanionReplay();
      final output = [
        visionLabReplayHeader,
        for (final frame in frames)
          visionLabReplayRow(frame, replay.evaluate(frame)),
      ];
      expect(
        '${output.join('\n')}\n',
        normalizeNewlines(await File(_baseline).readAsString()),
      );
      expect(
        frames
            .where((f) => !f.result.hasFace)
            .every((f) => !f.result.hasEyeData),
        isTrue,
      );
      native[1][calibrationIndex] = '';
      expect(() => parseVisionLabReplayFrames(native), throwsFormatException);
    },
  );

  test(
    'missing required columns and malformed values fail explicitly',
    () async {
      final rows = await readVisionLabReplayCsv(_fixture);
      expect(
        () => parseVisionLabReplayFrames([
          ['frame_idx', 'timestamp_ms'],
          ['0', '0'],
        ], requireRawEyeClosed: true),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'missing names',
            contains('raw_eye_closed'),
          ),
        ),
      );
      final invalid = rows.map((r) => List<String>.of(r)).toList();
      invalid[1][rows.first.indexOf('face_detected')] = 'maybe';
      expect(() => parseVisionLabReplayFrames(invalid), throwsFormatException);
      invalid[1][rows.first.indexOf('face_detected')] = 'true';
      invalid[1][rows.first.indexOf('pitch')] = 'NaN';
      expect(() => parseVisionLabReplayFrames(invalid), throwsFormatException);
      expect(
        () => parseVisionLabReplayFrames([rows.first, rows[1], rows[1]]),
        throwsFormatException,
      );
    },
  );

  test(
    'CLI output is deterministic for both windows and preserves fast columns',
    () async {
      final directory = await Directory.systemTemp.createTemp('dual_track_');
      addTearDown(() => directory.delete(recursive: true));
      final frozen = await readVisionLabReplayCsv(_baseline);
      final originalBytes = await File(_fixture).readAsBytes();
      for (final window in [2000, 3000]) {
        final first = await cli.runDualTrackLab(
          featurePath: _fixture,
          truthPath: _truth,
          outputDirectory: '${directory.path}/a$window',
          windowMs: window,
        );
        final second = await cli.runDualTrackLab(
          featurePath: _fixture,
          truthPath: _truth,
          outputDirectory: '${directory.path}/b$window',
          windowMs: window,
        );
        expect(first.length, 3);
        for (var i = 0; i < first.length; i++) {
          expect(
            await File(first[i]).readAsBytes(),
            await File(second[i]).readAsBytes(),
          );
        }
        final actual = await readVisionLabReplayCsv(first[0]);
        expect(actual.length, frozen.length);
        for (var i = 1; i < actual.length; i++) {
          expect(actual[i].take(4), frozen[i].take(4));
        }
        await expectLater(
          cli.runDualTrackLab(
            featurePath: _fixture,
            truthPath: _truth,
            outputDirectory: '${directory.path}/a$window',
            windowMs: window,
          ),
          throwsA(isA<FileSystemException>()),
        );
      }
      expect(await File(_fixture).readAsBytes(), originalBytes);
    },
  );

  test('metrics retain unknown frames and do not invent reading labels', () {
    final report = buildDualTrackLabReport(
      frames: [
        for (var i = 0; i < 4; i++)
          VisionLabFrame(
            frameIndex: i,
            timestampMs: i * 1000,
            rawState: 'normal',
          ),
      ],
      states: ['normal', 'drowsy_like', 'unknown_low_head', 'drowsy_like'],
      truth: const [
        VisionLabEvent(state: 'normal', startMs: 0, endMs: 2000),
        VisionLabEvent(state: 'sleeping', startMs: 2000, endMs: 4000),
      ],
      windowMs: 2000,
    );
    expect(report.metrics['tp_frames'], '1');
    expect(report.metrics['fp_frames'], '1');
    expect(report.metrics['fn_frames'], '1');
    expect(report.metrics['precision'], '0.500000');
    expect(report.metrics['reading_labels_available'], 'false');
    expect(report.metrics['reading_fp_frames'], '');
    expect(report.metrics['unknown_low_head_ratio'], '0.250000');
    expect(report.metrics['unknown_low_head_longest_ms'], '1000');
    expect(report.metrics['onset_delays_ms'], '1000');
  });

  test(
    'invalid CLI arguments return nonzero without producing output',
    () async {
      final previousExitCode = exitCode;
      try {
        exitCode = 0;
        await cli.main(['missing.csv', _truth, 'unused', '--window-ms=2500']);
        expect(exitCode, 64);
      } finally {
        exitCode = previousExitCode;
      }
    },
  );

  test('reading labels enable reading false-positive reporting', () {
    final report = buildDualTrackLabReport(
      frames: const [
        VisionLabFrame(frameIndex: 0, timestampMs: 0, rawState: 'normal'),
      ],
      states: ['drowsy_like'],
      truth: const [VisionLabEvent(state: 'reading', startMs: 0, endMs: 1000)],
      windowMs: 2000,
    );
    expect(report.metrics['reading_fp_frames'], '1');
    expect(report.metrics['reading_fp_events'], '1');
  });

  test('sleep-first CLI emits only sleeping, uncertain, or other', () async {
    final directory = await Directory.systemTemp.createTemp('sleep_first_');
    addTearDown(() => directory.delete(recursive: true));
    final files = await cli.runDualTrackLab(
      featurePath: _fixture,
      truthPath: _truth,
      outputDirectory: directory.path,
      windowMs: 2000,
      enableLongShortGate: true,
      enableSleepFirst: true,
    );

    expect(files, hasLength(3));
    expect(files.every((path) => path.contains('sleep_first_')), isTrue);
    final frames = await readVisionLabReplayCsv(files[0]);
    final sleepFirstColumn = frames.first.indexOf('sleep_first_state');
    expect(sleepFirstColumn, isNonNegative);
    expect(
      frames.skip(1).map((row) => row[sleepFirstColumn]).toSet(),
      everyElement(isIn({'sleeping', 'uncertain_low_head', 'other'})),
    );
    final events = await readGroundTruthEvents(files[1]);
    expect(
      events.map((event) => event.state).toSet(),
      everyElement(isIn({'sleeping', 'uncertain_low_head', 'other'})),
    );
  });

  test('sleep-first CLI replays and carries LiteRT person presence', () async {
    final directory = await Directory.systemTemp.createTemp(
      'sleep_first_mask_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final presence = File('${directory.path}/presence.csv');
    await presence.writeAsString(
      'frame_idx,timestamp_ms,person_mask_mean_confidence,'
      'person_mask_area_ratio,person_mask_centroid_x,'
      'person_mask_centroid_y,inference_ms\n'
      '22,4900,0.8,0.7,0.5,0.5,6.0\n',
    );
    final files = await cli.runDualTrackLab(
      featurePath: _fixture,
      truthPath: _truth,
      outputDirectory: '${directory.path}/output',
      windowMs: 2000,
      enablePresenceContext: true,
      enableLongShortGate: true,
      enableSleepFirst: true,
      personPresencePath: presence.path,
    );

    final rows = await readVisionLabReplayCsv(files[0]);
    final timestampColumn = rows.first.indexOf('timestamp_ms');
    final sampledColumn = rows.first.indexOf('person_presence_sampled');
    final presentColumn = rows.first.indexOf('person_present');
    final areaColumn = rows.first.indexOf('person_mask_area_ratio');
    final sampled = rows.firstWhere((row) => row[timestampColumn] == '4900');
    final carried = rows.firstWhere((row) => row[timestampColumn] == '5200');
    expect(sampled[sampledColumn], 'true');
    expect(sampled[presentColumn], 'true');
    expect(sampled[areaColumn], '0.7');
    expect(carried[sampledColumn], 'true');
    expect(carried[presentColumn], 'true');
  });
}
