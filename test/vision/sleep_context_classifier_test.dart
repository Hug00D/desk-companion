import 'package:flutter_test/flutter_test.dart';

import '../../tool/vision_lab_reclassify_sleep_context.dart';

SleepContextResult sample(
  SleepContextClassifier classifier,
  int ms, {
  double pitch = 0,
  double drop = 0,
  bool closed = true,
  bool face = true,
  bool pose = true,
  double? shoulderGap,
}) => classifier.classify(
  timestampMs: ms,
  hasFace: face,
  hasPose: pose,
  pitch: face ? pitch : null,
  noseYRatio: pose ? 0.36 + drop : null,
  rawEyeClosed: closed,
  shoulderGapRatio: shoulderGap,
);

void main() {
  group('shoulder evidence candidate', () {
    SleepContextClassifier candidate() => SleepContextClassifier(
      baselineNoseYRatio: 0.36,
      requireGeometryEvidence: true,
    );

    test('depth alone is unconfirmed rather than a sleep alert', () {
      final result = sample(candidate(), 0, drop: 0.2, shoulderGap: 0.3);
      expect(result.sleeping, isFalse);
      expect(result.unconfirmedDepth, isTrue);
    });

    test('depth plus near-shoulder head supports the static path', () {
      final result = sample(candidate(), 0, drop: 0.2, shoulderGap: 0.15);
      expect(result.staticSleeping, isTrue);
      expect(result.unconfirmedDepth, isFalse);
    });

    test('geometry alone without depth is insufficient', () {
      expect(
        sample(candidate(), 0, drop: 0.04, shoulderGap: 0).sleeping,
        isFalse,
      );
    });

    test(
      'face loss alone does not confirm depth; valid Pose can support it',
      () {
        expect(
          sample(candidate(), 0, face: false, drop: 0.2).sleeping,
          isFalse,
        );
        expect(
          sample(
            candidate(),
            0,
            face: false,
            drop: 0.2,
            shoulderGap: -0.02,
          ).sleeping,
          isTrue,
        );
        expect(
          sample(
            candidate(),
            0,
            pose: false,
            drop: 0.2,
            shoulderGap: 0,
          ).sleeping,
          isFalse,
        );
      },
    );

    test('nonfinite geometry is not evidence', () {
      for (final gap in [
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ]) {
        expect(
          sample(candidate(), 0, drop: 0.2, shoulderGap: gap).sleeping,
          isFalse,
        );
      }
    });

    test('stable dynamic trigger still works without shoulder geometry', () {
      final classifier = candidate();
      for (var ms = 0; ms <= 300; ms += 100) {
        sample(classifier, ms);
      }
      expect(
        sample(classifier, 400, pitch: 25, drop: 0.08).dynamicTriggered,
        isTrue,
      );
    });

    double? gap({
      double scale = 1,
      double? visibility = 1,
      double width = 200,
      double nose = 280,
      double height = 640,
    }) => calculateShoulderGapRatio(
      imageHeight: height * scale,
      noseY: nose * scale,
      noseVisibility: visibility,
      leftX: 100 * scale,
      leftY: 300 * scale,
      leftVisibility: visibility,
      rightX: (100 + width) * scale,
      rightY: 300 * scale,
      rightVisibility: visibility,
    );

    test('gap uses image-coordinate geometry and is scale invariant', () {
      expect(gap(), closeTo(0.1, 1e-12));
      expect(gap(scale: 2), closeTo(0.1, 1e-12));
      expect(gap(nose: 320), closeTo(-0.1, 1e-12));
    });

    test('missing or low visibility never produces geometry evidence', () {
      for (final visibility in [null, 0.49, double.nan, double.infinity, 1.1]) {
        expect(gap(visibility: visibility), isNull);
      }
      expect(gap(visibility: 0.5), isNotNull);
    });

    test(
      'invalid coordinates, image size or tiny shoulder span are rejected',
      () {
        expect(gap(width: 0), isNull);
        expect(gap(width: 20), isNull);
        expect(gap(nose: double.nan), isNull);
        expect(gap(height: 0), isNull);
      },
    );
  });

  test('stable closure arms at 300 ms and later descent triggers', () {
    final classifier = SleepContextClassifier(baselineNoseYRatio: 0.36);
    for (var ms = 0; ms <= 300; ms += 100) {
      expect(sample(classifier, ms, pitch: ms / 150).sleeping, isFalse);
    }
    expect(
      sample(classifier, 400, pitch: 25, drop: 0.08).dynamicTriggered,
      isTrue,
    );
  });

  test('closure shorter than 300 ms does not arm', () {
    final classifier = SleepContextClassifier(baselineNoseYRatio: 0.36);
    sample(classifier, 0);
    sample(classifier, 100);
    sample(classifier, 200);
    expect(sample(classifier, 300, pitch: 25, drop: 0.08).sleeping, isFalse);
  });

  test('moving closure blocks new arm but reproduces legacy trigger', () {
    for (final stable in [true, false]) {
      final classifier = SleepContextClassifier(
        baselineNoseYRatio: 0.36,
        requireStableArm: stable,
      );
      for (var ms = 0; ms <= 300; ms += 100) {
        sample(classifier, ms, pitch: ms * 0.04, drop: ms * 0.0001);
      }
      expect(
        sample(classifier, 400, pitch: 25, drop: 0.08).dynamicTriggered,
        !stable,
      );
    }
  });

  test('nose movement alone prevents arming', () {
    final classifier = SleepContextClassifier(baselineNoseYRatio: 0.36);
    for (var ms = 0; ms <= 300; ms += 100) {
      sample(classifier, ms, drop: ms * 0.0001);
    }
    expect(sample(classifier, 400, pitch: 25, drop: 0.08).sleeping, isFalse);
  });

  test('range detects excursion even when head returns to starting angle', () {
    final classifier = SleepContextClassifier(baselineNoseYRatio: 0.36);
    sample(classifier, 0);
    sample(classifier, 100, pitch: 5);
    sample(classifier, 200);
    sample(classifier, 300);
    expect(sample(classifier, 400, pitch: 25, drop: 0.08).sleeping, isFalse);
  });

  test('head settling can start a new full stable closure interval', () {
    final classifier = SleepContextClassifier(baselineNoseYRatio: 0.36);
    sample(classifier, 0);
    for (var ms = 100; ms <= 400; ms += 100) {
      sample(classifier, ms, pitch: 8);
    }
    expect(
      sample(classifier, 500, pitch: 25, drop: 0.08).dynamicTriggered,
      isTrue,
    );
  });

  test('open eye or missing detections interrupt closure evidence', () {
    for (final interruption in ['open', 'face', 'pose']) {
      final classifier = SleepContextClassifier(baselineNoseYRatio: 0.36);
      sample(classifier, 0);
      sample(classifier, 100);
      sample(
        classifier,
        200,
        closed: interruption != 'open',
        face: interruption != 'face',
        pose: interruption != 'pose',
      );
      sample(classifier, 300);
      expect(sample(classifier, 400, pitch: 25, drop: 0.08).sleeping, isFalse);
    }
  });

  test('static deep-head path still works without face', () {
    final classifier = SleepContextClassifier(baselineNoseYRatio: 0.36);
    final result = sample(classifier, 0, face: false, drop: 0.14);
    expect(result.staticSleeping, isTrue);
    expect(result.dynamicSleeping, isFalse);
  });

  test('armed evidence expires and upright opening cancels it', () {
    for (final expire in [true, false]) {
      final classifier = SleepContextClassifier(baselineNoseYRatio: 0.36);
      for (var ms = 0; ms <= 300; ms += 100) {
        sample(classifier, ms);
      }
      if (expire) {
        expect(
          sample(classifier, 2301, pitch: 25, drop: 0.08).sleeping,
          isFalse,
        );
      } else {
        for (var ms = 400; ms <= 900; ms += 100) {
          sample(classifier, ms, closed: false);
        }
        expect(
          sample(classifier, 1000, pitch: 25, drop: 0.08).sleeping,
          isFalse,
        );
      }
    }
  });

  test('latch recovery still uses 2500 ms upright regardless of blinks', () {
    final classifier = SleepContextClassifier(baselineNoseYRatio: 0.36);
    for (var ms = 0; ms <= 300; ms += 100) {
      sample(classifier, ms);
    }
    sample(classifier, 400, pitch: 25, drop: 0.08);
    for (var ms = 500; ms < 3000; ms += 100) {
      expect(sample(classifier, ms, closed: ms % 200 == 0).sleeping, isTrue);
    }
    expect(sample(classifier, 3000).sleeping, isFalse);
  });
}
