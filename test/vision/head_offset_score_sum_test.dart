import 'dart:io';

import 'package:desk_companion/vision/companion_state_evaluator.dart';
import 'package:desk_companion/vision/dual_track_context_classifier.dart';
import 'package:desk_companion/vision/head_offset_detector.dart';
import 'package:desk_companion/vision/vision_lab_replay.dart';
import 'package:desk_companion/vision/vision_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/vision_lab_dual_track.dart' as cli;

VisionResult vision({
  double? score = 0,
  bool face = true,
  bool pose = true,
  bool calibrating = false,
  double visibility = 1,
  double noseX = 320,
  double noseY = 220,
  double shoulderX = 320,
}) => VisionResult.fromNativeMap({
  'hasFace': face,
  'hasPose': pose,
  'imageWidth': 640.0,
  'imageHeight': 640.0,
  'poseNoseX': noseX,
  'poseNoseY': noseY,
  'poseNoseVisibility': visibility,
  'lsX': shoulderX - 100,
  'lsY': 350.0,
  'lsVisibility': visibility,
  'rsX': shoulderX + 100,
  'rsY': 350.0,
  'rsVisibility': visibility,
  'headPitch': 0.0,
  'headOffsetScore': score,
  'headOffsetCalibrating': calibrating,
  'leftEye': 0.8,
  'rightEye': 0.8,
});

class Sequence {
  final detector = HeadOffsetDetector(useScoreSum: true);
  int ms = 0;
  int count = 0;

  HeadOffsetDetectionResult step(
    double? score, {
    bool face = true,
    bool pose = true,
    bool fill = true,
    bool calibrating = false,
    int gapMs = 100,
  }) {
    ms += gapMs;
    final result = detector.evaluate(
      result: vision(
        score: score,
        face: face,
        pose: pose,
        calibrating: calibrating,
      ),
      previousDistractedFrameCount: count,
      observedAt: DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
      allowMissingFaceFill: fill,
    );
    count = result.distractedFrameCount;
    return result;
  }

  HeadOffsetDetectionResult feed(List<double> scores) {
    HeadOffsetDetectionResult? result;
    for (final score in scores) {
      result = step(score);
    }
    return result!;
  }
}

DualTrackContextResult classify(
  DualTrackContextClassifier classifier,
  int ms, {
  double score = 100,
  bool face = true,
  bool pose = true,
  double visibility = 1,
  double noseX = 320,
  double noseY = 220,
  double shoulderX = 320,
  bool posture = false,
  CompanionStatus fast = CompanionStatus.normal,
}) => classifier.classify(
  timestampMs: ms,
  result: vision(
    score: score,
    face: face,
    pose: pose,
    visibility: visibility,
    noseX: noseX,
    noseY: noseY,
    shoulderX: shoulderX,
  ),
  fastState: CompanionState(status: fast, cause: CompanionCause.none),
  rawEyeClosed: false,
  strongPostureEvidence: posture,
);

void main() {
  test(
    'five scores total 275 inclusive enters with two measured high scores',
    () {
      final result = Sequence().feed([0, 0, 100, 100, 75]);
      expect(result.state, HeadOffsetState.distracted);
      expect(result.scoreSum, 275);
      expect(result.scoreWindowSamples, 5);
      expect(result.measuredHighSamples, 3);
      expect(result.scoreImputed, isFalse);
    },
  );

  test('a total below 275 does not enter', () {
    final result = Sequence().feed([0, 0, 100, 100, 74]);
    expect(result.state, HeadOffsetState.normal);
    expect(result.scoreSum, 274);
  });

  test('an incomplete window cannot enter even at 400', () {
    final result = Sequence().feed([100, 100, 100, 100]);
    expect(result.state, HeadOffsetState.normal);
    expect(result.scoreSum, 400);
    expect(result.scoreWindowSamples, 4);
  });

  test('five scores of 50 and one high outlier cannot start distraction', () {
    expect(Sequence().feed([50, 50, 50, 50, 50]).state, HeadOffsetState.normal);
    final singleSpike = Sequence().feed([50, 50, 50, 50, 100]);
    expect(singleSpike.scoreSum, 300);
    expect(singleSpike.measuredHighSamples, 1);
    expect(singleSpike.state, HeadOffsetState.normal);
  });

  test('the sum window rolls without accumulating old observations', () {
    final sequence = Sequence();
    sequence.feed([100, 100, 0, 0, 0]);
    final result = sequence.step(0);
    expect(result.scoreSum, 100);
    expect(result.scoreWindowSamples, 5);
    expect(result.measuredHighSamples, 1);
    expect(result.state, HeadOffsetState.normal);
  });

  test('two actual peaks and three missing-face fills can enter', () {
    final sequence = Sequence();
    sequence.feed([100, 100]);
    sequence.step(null, face: false);
    sequence.step(null, face: false);
    final result = sequence.step(null, face: false);
    expect(result.scoreSum, 350);
    expect(result.measuredHighSamples, 2);
    expect(result.scoreUsed, 50);
    expect(result.scoreImputed, isTrue);
    expect(result.state, HeadOffsetState.distracted);
  });

  test('one spike plus missing frames cannot start distraction', () {
    final sequence = Sequence();
    sequence.step(100);
    for (var i = 0; i < 10; i++) {
      final result = sequence.step(100, face: false);
      expect(result.state, HeadOffsetState.unavailable);
      expect(result.scoreImputed, isFalse);
      expect(result.scoreSum, 0);
    }
  });

  test('missing from startup never invents measured evidence', () {
    final sequence = Sequence();
    for (var i = 0; i < 10; i++) {
      final result = sequence.step(100, face: false);
      expect(result.state, HeadOffsetState.unavailable);
      expect(result.measuredHighSamples, 0);
      expect(result.scoreImputed, isFalse);
    }
  });

  test(
    'fills retain an established turn but never renew its two-second limit',
    () {
      final sequence = Sequence();
      sequence.feed([100, 100, 100, 100, 100]);
      for (var i = 0; i < 20; i++) {
        final result = sequence.step(null, face: false);
        expect(result.state, HeadOffsetState.distracted);
        expect(result.scoreImputed, isTrue);
        if (i >= 4) {
          expect(result.scoreSum, 250);
          expect(result.measuredHighSamples, 0);
        }
      }
      final expired = sequence.step(null, face: false);
      expect(expired.state, HeadOffsetState.unavailable);
      expect(expired.scoreImputed, isFalse);
      expect(expired.scoreSum, 0);
    },
  );

  test('forbidden fill or body loss clears old evidence', () {
    for (final bodyGone in [true, false]) {
      final sequence = Sequence();
      sequence.feed([100, 100, 100, 100, 100]);
      final result = sequence.step(
        null,
        face: false,
        pose: !bodyGone,
        fill: bodyGone,
      );
      expect(result.state, HeadOffsetState.unavailable);
      expect(result.scoreSum, 0);
      expect(sequence.step(100).state, HeadOffsetState.normal);
    }
  });

  test(
    'standalone score sum does not fill without explicit caller permission',
    () {
      final detector = HeadOffsetDetector(useScoreSum: true);
      for (var ms = 0; ms <= 400; ms += 100) {
        detector.evaluate(
          result: vision(score: 100),
          previousDistractedFrameCount: 0,
          observedAt: DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
        );
      }
      final result = detector.evaluate(
        result: vision(face: false),
        previousDistractedFrameCount: 1,
        observedAt: DateTime.fromMillisecondsSinceEpoch(500, isUtc: true),
      );
      expect(result.state, HeadOffsetState.unavailable);
      expect(result.scoreImputed, isFalse);
    },
  );

  test('invalid or missing visible-face score is not replaced with 50', () {
    for (final score in [null, double.nan, double.infinity]) {
      final sequence = Sequence();
      sequence.feed([100, 100, 100, 100, 100]);
      final result = sequence.step(score);
      expect(result.state, HeadOffsetState.unavailable);
      expect(result.scoreImputed, isFalse);
      expect(result.scoreSum, 0);
    }
  });

  test('two recentred observations release and clear the score window', () {
    final sequence = Sequence();
    sequence.feed([100, 100, 100, 100, 100]);
    expect(sequence.step(30).state, HeadOffsetState.distracted);
    final result = sequence.step(30);
    expect(result.state, HeadOffsetState.normal);
    expect(result.scoreSum, 0);
    expect(sequence.step(null, face: false).scoreImputed, isFalse);
  });

  test('rapid repeated measured turns re-arm without a growing history', () {
    final sequence = Sequence();
    for (var i = 0; i < 3; i++) {
      expect(
        sequence.feed([0, 0, 100, 100, 80]).state,
        HeadOffsetState.distracted,
      );
      sequence.step(0);
      expect(sequence.step(0).state, HeadOffsetState.normal);
    }
  });

  test('stable six-second off-axis gaze releases until recentering', () {
    final sequence = Sequence();
    sequence.feed([60, 60, 60, 60, 60]);
    HeadOffsetDetectionResult? result;
    for (var i = 0; i < 65; i++) {
      result = sequence.step(60);
    }
    expect(result!.state, HeadOffsetState.normal);
    expect(sequence.step(null, face: false).scoreImputed, isFalse);
    expect(sequence.step(60).state, HeadOffsetState.normal);
    sequence.step(0);
    expect(
      sequence.feed([60, 60, 60, 60, 60]).state,
      HeadOffsetState.distracted,
    );
  });

  test('fills do not count as stable gaze observations', () {
    final sequence = Sequence();
    sequence.feed([60, 60, 60, 60, 60]);
    for (var cycle = 0; cycle < 4; cycle++) {
      for (var i = 0; i < 10; i++) {
        expect(
          sequence.step(null, face: false).state,
          HeadOffsetState.distracted,
        );
      }
      expect(sequence.feed([60, 60]).state, HeadOffsetState.distracted);
    }
  });

  test('a gap over 500 ms clears evidence while exactly 500 does not', () {
    for (final gap in [500, 501]) {
      final sequence = Sequence();
      sequence.feed([100, 100, 100, 100, 100]);
      final result = sequence.step(100, gapMs: gap);
      expect(
        result.state,
        gap == 500 ? HeadOffsetState.distracted : HeadOffsetState.normal,
      );
      expect(result.scoreWindowSamples, gap == 500 ? 5 : 1);
    }
  });

  test('reset and calibration clear the sum and any fill eligibility', () {
    final sequence = Sequence();
    sequence.feed([100, 100, 100, 100, 100]);
    sequence.detector.reset();
    expect(sequence.step(null, face: false).scoreImputed, isFalse);
    sequence.feed([100, 100, 100, 100, 100]);
    expect(
      sequence.step(100, calibrating: true).state,
      HeadOffsetState.unavailable,
    );
    expect(sequence.step(null, face: false).scoreImputed, isFalse);
  });

  test('non-increasing timestamps are rejected', () {
    final sequence = Sequence();
    sequence.step(100);
    expect(() => sequence.step(100, gapMs: 0), throwsArgumentError);
    expect(() => sequence.step(100, gapMs: -1), throwsArgumentError);
  });

  test('offline head sum requires presence arbitration', () {
    expect(
      () => DualTrackContextClassifier(enableHeadScoreSum: true),
      throwsArgumentError,
    );
  });

  test('presence arbitration forbids imputation on unreliable geometry', () {
    final classifier = DualTrackContextClassifier(
      enablePresenceContext: true,
      enableHeadScoreSum: true,
    );
    for (var ms = 0; ms <= 500; ms += 100) {
      classify(classifier, ms);
    }
    final result = classify(classifier, 600, face: false, visibility: 0.49);
    expect(result.headScore!.scoreImputed, isFalse);
    expect(result.finalState, 'unknown_low_head');
  });

  test('relative descent and posture override the head-turn candidate', () {
    for (final posture in [false, true]) {
      final classifier = DualTrackContextClassifier(
        enablePresenceContext: true,
        enableHeadScoreSum: true,
      );
      for (var ms = 0; ms <= 500; ms += 100) {
        classify(classifier, ms, noseY: ms == 500 ? 280 : 220);
      }
      final result = classify(classifier, 600, face: false, posture: posture);
      expect(result.headScore!.scoreImputed, isFalse);
      expect(result.headScore!.state, HeadOffsetState.unavailable);
      expect(result.finalState, 'unknown_low_head');
      final confirmed = classify(
        classifier,
        1100,
        face: false,
        posture: posture,
      );
      expect(confirmed.headScore!.scoreImputed, isFalse);
      expect(confirmed.finalState, posture ? 'sleeping' : 'unknown_low_head');
    }
  });

  test('side exit and confirmed absence never become imputed distraction', () {
    final classifier = DualTrackContextClassifier(
      enablePresenceContext: true,
      enableHeadScoreSum: true,
    );
    for (var ms = 0; ms <= 400; ms += 100) {
      classify(classifier, ms);
    }
    classify(classifier, 500, noseX: 60, shoulderX: 160);
    for (var ms = 600; ms <= 1200; ms += 100) {
      final result = classify(
        classifier,
        ms,
        face: false,
        noseX: 60,
        shoulderX: 160,
      );
      expect(result.headScore!.scoreImputed, isFalse);
      expect(
        result.finalState,
        ms < 1100 ? 'unknown_low_head' : 'user_missing',
      );
    }
  });

  test('head sum replaces legacy distraction only in opt-in output', () {
    for (final enabled in [false, true]) {
      final classifier = DualTrackContextClassifier(
        enablePresenceContext: true,
        enableHeadScoreSum: enabled,
      );
      final result = classify(
        classifier,
        0,
        score: 0,
        fast: CompanionStatus.distracted,
      );
      expect(result.finalState, enabled ? 'normal' : 'distracted');
      expect(result.headScore == null, !enabled);
    }
  });

  test(
    'candidate replay is deterministic and preserves original fast columns and input',
    () async {
      const fixture = 'test/fixtures/vision/dual_track_features.csv';
      const truth = 'test/fixtures/vision/dual_track_truth.csv';
      final directory = await Directory.systemTemp.createTemp('head_sum_');
      addTearDown(() => directory.delete(recursive: true));
      final original = await File(fixture).readAsBytes();
      final frozen = await readVisionLabReplayCsv(
        'test/fixtures/vision/dual_track_replay_baseline.csv',
      );
      for (final window in [2000, 3000]) {
        final a = await cli.runDualTrackLab(
          featurePath: fixture,
          truthPath: truth,
          outputDirectory: '${directory.path}/a$window',
          windowMs: window,
          enablePresenceContext: true,
          enableHeadScoreSum: true,
        );
        final b = await cli.runDualTrackLab(
          featurePath: fixture,
          truthPath: truth,
          outputDirectory: '${directory.path}/b$window',
          windowMs: window,
          enablePresenceContext: true,
          enableHeadScoreSum: true,
        );
        for (var i = 0; i < a.length; i++) {
          expect(
            await File(a[i]).readAsBytes(),
            await File(b[i]).readAsBytes(),
          );
          expect(a[i], contains('_presence_headsum.csv'));
        }
        final rows = await readVisionLabReplayCsv(a[0]);
        expect(rows.first, contains('head_score_imputed'));
        for (var i = 1; i < rows.length; i++) {
          expect(rows[i].take(4), frozen[i].take(4));
        }
      }
      expect(await File(fixture).readAsBytes(), original);
    },
  );

  test(
    'CLI rejects unsafe head sum, duplicate flags and unknown options',
    () async {
      final previous = exitCode;
      try {
        for (final flags in [
          ['--head-score-sum'],
          ['--presence-context', '--presence-context'],
          ['--other'],
        ]) {
          exitCode = 0;
          await cli.main([
            'missing.csv',
            'missing.csv',
            'unused',
            '--window-ms=2000',
            ...flags,
          ]);
          expect(exitCode, 64);
        }
      } finally {
        exitCode = previous;
      }
    },
  );
}
