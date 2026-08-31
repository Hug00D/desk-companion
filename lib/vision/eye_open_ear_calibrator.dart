import 'frame_classifier.dart';

class EyeOpenEarSample {
  const EyeOpenEarSample({required this.timestampMs, required this.features});

  final int timestampMs;
  final FrameFeatures features;
}

class EyeOpenEarCalibration {
  const EyeOpenEarCalibration({
    required this.leftOpenEar,
    required this.rightOpenEar,
    required this.sampleCount,
    required this.usedFallback,
  });

  final double leftOpenEar;
  final double rightOpenEar;
  final int sampleCount;
  final bool usedFallback;
}

/// Derives a deterministic per-video open-eye reference before classification.
///
/// The 90th percentile ignores ordinary blink samples without trusting one
/// potentially noisy maximum. Calibration remains separate from
/// [FrameClassifier], so every classified row still depends only on that row
/// and the fixed run configuration returned here.
class EyeOpenEarCalibrator {
  const EyeOpenEarCalibrator({
    this.calibrationDurationMs = 4000,
    this.percentile = 0.90,
    this.minimumSampleCount = 30,
    this.maxCalibrationAbsPitch = 15,
    this.closedEyeEar = 0.13,
    this.minimumOpenClosedGap = 0.02,
    this.fallbackOpenEyeEar = 0.27,
  });

  final int calibrationDurationMs;
  final double percentile;
  final int minimumSampleCount;
  final double maxCalibrationAbsPitch;
  final double closedEyeEar;
  final double minimumOpenClosedGap;
  final double fallbackOpenEyeEar;

  EyeOpenEarCalibration calibrate(Iterable<EyeOpenEarSample> samples) {
    final leftValues = <double>[];
    final rightValues = <double>[];

    for (final sample in samples) {
      final features = sample.features;
      final leftEar = features.earLeft;
      final rightEar = features.earRight;
      final pitch = features.pitch?.abs();
      if (sample.timestampMs >= calibrationDurationMs ||
          !features.faceDetected ||
          leftEar == null ||
          rightEar == null ||
          (pitch != null && pitch >= maxCalibrationAbsPitch)) {
        continue;
      }
      leftValues.add(leftEar);
      rightValues.add(rightEar);
    }

    if (leftValues.length < minimumSampleCount) {
      return EyeOpenEarCalibration(
        leftOpenEar: fallbackOpenEyeEar,
        rightOpenEar: fallbackOpenEyeEar,
        sampleCount: leftValues.length,
        usedFallback: true,
      );
    }

    final leftOpenEar = _quantile(leftValues, percentile);
    final rightOpenEar = _quantile(rightValues, percentile);
    final minimumOpenEar = closedEyeEar + minimumOpenClosedGap;
    if (leftOpenEar < minimumOpenEar || rightOpenEar < minimumOpenEar) {
      return EyeOpenEarCalibration(
        leftOpenEar: fallbackOpenEyeEar,
        rightOpenEar: fallbackOpenEyeEar,
        sampleCount: leftValues.length,
        usedFallback: true,
      );
    }

    return EyeOpenEarCalibration(
      leftOpenEar: leftOpenEar,
      rightOpenEar: rightOpenEar,
      sampleCount: leftValues.length,
      usedFallback: false,
    );
  }

  double _quantile(List<double> values, double quantile) {
    final sorted = List<double>.of(values)..sort();
    final position = (sorted.length - 1) * quantile.clamp(0.0, 1.0);
    final lowerIndex = position.floor();
    final upperIndex = position.ceil();
    if (lowerIndex == upperIndex) return sorted[lowerIndex];
    final fraction = position - lowerIndex;
    return sorted[lowerIndex] +
        (sorted[upperIndex] - sorted[lowerIndex]) * fraction;
  }
}
