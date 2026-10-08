import 'dart:io';

import 'package:desk_companion/vision/disappearance_context_classifier.dart';
import 'package:desk_companion/vision/dual_track_context_classifier.dart';
import 'package:desk_companion/vision/companion_state_evaluator.dart';
import 'package:desk_companion/vision/vision_result.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:desk_companion/vision/vision_lab_replay.dart';

import '../../tool/vision_lab_dual_track.dart' as cli;

VisionResult frame({
  bool face = true,
  bool pose = true,
  double x = 0.5,
  double bodyX = 0.5,
  double noseY = 0.3,
  double shoulderY = 0.5,
  double visibility = 1,
}) => VisionResult.fromNativeMap({
  'hasFace': face,
  'hasPose': pose,
  'imageWidth': 640.0,
  'imageHeight': 640.0,
  'poseNoseX': x * 640,
  'poseNoseY': noseY * 640,
  'poseNoseVisibility': visibility,
  'lsX': (bodyX + 0.1) * 640,
  'lsY': shoulderY * 640,
  'lsVisibility': visibility,
  'rsX': (bodyX - 0.1) * 640,
  'rsY': shoulderY * 640,
  'rsVisibility': visibility,
  'headPitch': 0.0,
  'headYaw': 0.0,
  'headOffsetScore': 0.0,
  'leftEye': 0.8,
  'rightEye': 0.8,
});

DisappearanceContextResult observe(
  DisappearanceContextClassifier classifier,
  int ms, {
  bool face = true,
  bool pose = true,
  double x = 0.5,
  double bodyX = 0.5,
  double noseY = 0.3,
  double shoulderY = 0.5,
  bool reliable = true,
  bool posture = false,
}) => classifier.classify(
  timestampMs: ms,
  result: frame(
    face: face,
    pose: pose,
    x: x,
    bodyX: bodyX,
    noseY: noseY,
    shoulderY: shoulderY,
  ),
  reliablePose: reliable && pose,
  confirmedSleepPosture: posture,
);

void warm(DisappearanceContextClassifier classifier) {
  for (final ms in [0, 200, 400]) {
    observe(classifier, ms);
  }
}

void sideExit(DisappearanceContextClassifier classifier, {bool right = false}) {
  warm(classifier);
  observe(classifier, 500, x: right ? 0.9 : 0.1, bodyX: right ? 0.7 : 0.3);
  observe(classifier, 600, face: false);
}

void headDescent(DisappearanceContextClassifier classifier) {
  warm(classifier);
  observe(classifier, 500, noseY: 0.4);
  observe(classifier, 600, face: false, noseY: 0.4);
}

void main() {
  test('side exit confirms at 500 ms, not 499 ms', () {
    final classifier = DisappearanceContextClassifier();
    sideExit(classifier);
    final before = observe(classifier, 1099, face: false);
    expect(before.state, DisappearanceState.pending);
    expect(before.sideExit, isTrue);
    expect(
      observe(classifier, 1100, face: false).state,
      DisappearanceState.away,
    );
  });

  test('left and right exits use matching head and body displacement', () {
    for (final right in [false, true]) {
      final classifier = DisappearanceContextClassifier();
      sideExit(classifier, right: right);
      observe(classifier, 900, face: false);
      expect(
        observe(classifier, 1100, face: false).state,
        DisappearanceState.away,
      );
    }
  });

  test('head turn without body departure is not an exit', () {
    final classifier = DisappearanceContextClassifier();
    warm(classifier);
    observe(classifier, 500, x: 0.1);
    observe(classifier, 600, face: false);
    observe(classifier, 900, face: false);
    final lost = observe(classifier, 1100, face: false);
    expect(lost.sideExit, isFalse);
    expect(lost.state, DisappearanceState.unknown);
  });

  test('brief face loss is pending rather than away or sleep', () {
    final classifier = DisappearanceContextClassifier();
    warm(classifier);
    expect(
      observe(classifier, 600, face: false).state,
      DisappearanceState.pending,
    );
    expect(observe(classifier, 700).reason, 'confirming_return');
    observe(classifier, 1000);
    expect(observe(classifier, 1200).state, DisappearanceState.none);
  });

  test('absence with no trustworthy history cannot establish departure', () {
    final classifier = DisappearanceContextClassifier();
    for (final ms in [0, 200, 500, 800]) {
      final result = observe(classifier, ms, face: false, pose: false);
      expect(result.reliableHistory, isFalse);
      expect(result.relativeDescent, isFalse);
      expect(result.state, isNot(DisappearanceState.away));
    }
  });

  test('missing or unreliable points do not establish trajectory', () {
    final classifier = DisappearanceContextClassifier();
    warm(classifier);
    observe(classifier, 500, x: 0.1, bodyX: 0.3, noseY: 0.5, reliable: false);
    observe(classifier, 600, face: false);
    observe(classifier, 900, face: false);
    final result = observe(classifier, 1100, face: false);
    expect(result.relativeDescent, isFalse);
    expect(result.sideExit, isFalse);
    expect(result.state, DisappearanceState.unknown);
  });

  test('whole-body vertical movement is not relative head descent', () {
    final classifier = DisappearanceContextClassifier();
    warm(classifier);
    observe(classifier, 500, noseY: 0.4, shoulderY: 0.6);
    observe(classifier, 600, face: false);
    observe(classifier, 900, face: false);
    expect(observe(classifier, 1100, face: false).relativeDescent, isFalse);
  });

  test('descent without independent posture is only a sleep candidate', () {
    final classifier = DisappearanceContextClassifier();
    headDescent(classifier);
    observe(classifier, 900, face: false);
    final result = observe(classifier, 1100, face: false);
    expect(result.state, DisappearanceState.sleepCandidate);
    expect(result.sleepSupported, isFalse);
  });

  test('descent plus confirmed posture supports missing-face sleep', () {
    final classifier = DisappearanceContextClassifier();
    headDescent(classifier);
    observe(classifier, 900, face: false, posture: true);
    final result = observe(classifier, 1100, face: false);
    expect(result.state, DisappearanceState.sleepCandidate);
    expect(result.sleepSupported, isTrue);
  });

  test('expired reliable body evidence stops supporting sleep', () {
    final classifier = DisappearanceContextClassifier();
    headDescent(classifier);
    observe(classifier, 900, face: false, posture: true);
    observe(classifier, 1100, face: false, pose: false);
    final result = observe(classifier, 1401, face: false, pose: false);
    expect(result.relativeDescent, isTrue);
    expect(result.sleepSupported, isFalse);
    expect(result.state, isNot(DisappearanceState.away));
  });

  test('full absence without descent can confirm away', () {
    final classifier = DisappearanceContextClassifier();
    warm(classifier);
    observe(classifier, 600, face: false, pose: false);
    observe(classifier, 900, face: false, pose: false);
    final result = observe(classifier, 1100, face: false, pose: false);
    expect(result.state, DisappearanceState.away);
    expect(result.reason, 'fully_absent_without_descent');
  });

  test('chair pose cannot replace the observed exit history', () {
    final classifier = DisappearanceContextClassifier();
    sideExit(classifier);
    observe(classifier, 900, face: false);
    observe(classifier, 1100, face: false);
    for (var ms = 1300; ms <= 5000; ms += 200) {
      expect(
        observe(classifier, ms, face: false, noseY: 0.5, posture: true).state,
        DisappearanceState.away,
      );
    }
  });

  test('side departure takes precedence over an accompanying descent', () {
    final classifier = DisappearanceContextClassifier();
    warm(classifier);
    observe(classifier, 500, x: 0.1, bodyX: 0.3, noseY: 0.4);
    observe(classifier, 600, face: false);
    observe(classifier, 900, face: false, posture: true);
    final result = observe(classifier, 1100, face: false);
    expect(result.relativeDescent, isTrue);
    expect(result.state, DisappearanceState.away);
  });

  test(
    'recovery needs 500 ms and is not blocked by a lowered visible head',
    () {
      final classifier = DisappearanceContextClassifier();
      sideExit(classifier);
      observe(classifier, 900, face: false);
      observe(classifier, 1100, face: false);
      expect(
        observe(classifier, 1200, noseY: 0.4).state,
        DisappearanceState.away,
      );
      observe(classifier, 1500, noseY: 0.4);
      expect(
        observe(classifier, 1699, noseY: 0.4).state,
        DisappearanceState.away,
      );
      expect(
        observe(classifier, 1700, noseY: 0.4).state,
        DisappearanceState.none,
      );
    },
  );

  test('an interrupted return does not release away', () {
    final classifier = DisappearanceContextClassifier();
    sideExit(classifier);
    observe(classifier, 900, face: false);
    observe(classifier, 1100, face: false);
    observe(classifier, 1200);
    expect(
      observe(classifier, 1400, face: false).state,
      DisappearanceState.away,
    );
    expect(observe(classifier, 1500).state, DisappearanceState.away);
    observe(classifier, 1800);
    expect(observe(classifier, 2000).state, DisappearanceState.none);
  });

  test('a timestamp gap cannot carry an old exit into a new session', () {
    final classifier = DisappearanceContextClassifier();
    sideExit(classifier);
    final result = observe(classifier, 2000, face: false);
    expect(result.sideExit, isFalse);
    expect(result.reliableHistory, isFalse);
    expect(result.state, DisappearanceState.pending);
  });

  test('old reading descent expires before later face loss', () {
    final classifier = DisappearanceContextClassifier();
    warm(classifier);
    observe(classifier, 500, noseY: 0.4);
    for (var ms = 700; ms <= 2500; ms += 200) {
      observe(classifier, ms);
    }
    final result = observe(classifier, 2600, face: false);
    expect(result.relativeDescent, isFalse);
  });

  test('reset clears temporal evidence and invalid timestamps fail', () {
    final classifier = DisappearanceContextClassifier();
    sideExit(classifier);
    classifier.reset();
    final result = observe(classifier, 0, face: false);
    expect(result.reliableHistory, isFalse);
    expect(result.sideExit, isFalse);
    expect(() => observe(classifier, 0), throwsArgumentError);
    expect(() => observe(classifier, -1), throwsArgumentError);
  });

  test(
    'enabled arbitration overrides stale fast sleep but keeps fast inputs',
    () {
      final classifier = DualTrackContextClassifier(
        enablePresenceContext: true,
      );
      const stale = CompanionState(
        status: CompanionStatus.sleeping,
        cause: CompanionCause.postureDown,
      );
      DualTrackContextResult sample(
        int ms,
        VisionResult result, {
        bool strong = false,
      }) => classifier.classify(
        timestampMs: ms,
        result: result,
        fastState: stale,
        rawEyeClosed: false,
        strongPostureEvidence: strong,
      );
      for (final ms in [0, 200, 400]) {
        sample(ms, frame());
      }
      sample(500, frame(x: 0.1, bodyX: 0.3));
      expect(sample(600, frame(face: false)).finalState, 'unknown_low_head');
      sample(900, frame(face: false));
      expect(
        sample(1100, frame(face: false), strong: true).finalState,
        'user_missing',
      );
      classifier.reset();
      expect(sample(0, frame()).disappearance!.state, DisappearanceState.none);
    },
  );

  test(
    'enabled arbitration treats descent-only as unknown, not automatic sleep',
    () {
      final classifier = DualTrackContextClassifier(
        enablePresenceContext: true,
      );
      DualTrackContextResult sample(
        int ms,
        VisionResult result, {
        bool strong = false,
      }) => classifier.classify(
        timestampMs: ms,
        result: result,
        fastState: CompanionState.normal,
        rawEyeClosed: false,
        strongPostureEvidence: strong,
      );
      for (final ms in [0, 200, 400]) {
        sample(ms, frame());
      }
      sample(500, frame(noseY: 0.4));
      sample(600, frame(face: false));
      sample(900, frame(face: false));
      expect(sample(1100, frame(face: false)).finalState, 'unknown_low_head');
      expect(
        sample(1200, frame(face: false), strong: true).finalState,
        'sleeping',
      );
    },
  );

  test(
    'presence CLI is opt-in, keeps fast columns and has separate deterministic output',
    () async {
      final directory = await Directory.systemTemp.createTemp('presence_cli_');
      addTearDown(() => directory.delete(recursive: true));
      const features = 'test/fixtures/vision/dual_track_features.csv';
      const truth = 'test/fixtures/vision/dual_track_truth.csv';
      final original = await File(features).readAsBytes();
      for (final window in [2000, 3000]) {
        final disabled = await cli.runDualTrackLab(
          featurePath: features,
          truthPath: truth,
          outputDirectory: '${directory.path}/a',
          windowMs: window,
        );
        final enabled = await cli.runDualTrackLab(
          featurePath: features,
          truthPath: truth,
          outputDirectory: '${directory.path}/a',
          windowMs: window,
          enablePresenceContext: true,
        );
        final repeated = await cli.runDualTrackLab(
          featurePath: features,
          truthPath: truth,
          outputDirectory: '${directory.path}/b',
          windowMs: window,
          enablePresenceContext: true,
        );
        expect(enabled.every((path) => path.endsWith('_presence.csv')), isTrue);
        for (var i = 0; i < enabled.length; i++) {
          expect(
            await File(enabled[i]).readAsBytes(),
            await File(repeated[i]).readAsBytes(),
          );
        }
        final before = await readVisionLabReplayCsv(disabled[0]);
        final after = await readVisionLabReplayCsv(enabled[0]);
        expect(before.first, isNot(contains('presence_context')));
        expect(after.first, contains('relative_descent_evidence'));
        expect(after.length, before.length);
        for (var i = 1; i < before.length; i++) {
          expect(after[i].take(4), before[i].take(4));
        }
        await expectLater(
          cli.runDualTrackLab(
            featurePath: features,
            truthPath: truth,
            outputDirectory: '${directory.path}/a',
            windowMs: window,
            enablePresenceContext: true,
          ),
          throwsA(isA<FileSystemException>()),
        );
      }
      expect(await File(features).readAsBytes(), original);
    },
  );

  test('CLI accepts explicit presence flag and rejects unknown flags', () async {
    final directory = await Directory.systemTemp.createTemp('presence_args_');
    addTearDown(() => directory.delete(recursive: true));
    final previous = exitCode;
    try {
      exitCode = 0;
      final arguments = [
        'test/fixtures/vision/dual_track_features.csv',
        'test/fixtures/vision/dual_track_truth.csv',
        directory.path,
        '--window-ms=2000',
        '--presence-context',
      ];
      await cli.main(arguments);
      expect(exitCode, 0);
      expect(
        await File(
          '${directory.path}/dual_track_frames_2000_dual_track_features_presence.csv',
        ).exists(),
        isTrue,
      );
      arguments[4] = '--unknown';
      await cli.main(arguments);
      expect(exitCode, 64);
    } finally {
      exitCode = previous;
    }
  });
}
