import 'dart:math' as math;

/// Adaptive low-pass filter that reduces stationary jitter without adding as
/// much lag while the signal is moving quickly.
class OneEuroFilter {
  OneEuroFilter({
    this.minCutoff = 1.0,
    this.beta = 0.0,
    this.derivativeCutoff = 1.0,
  });

  final double minCutoff;
  final double beta;
  final double derivativeCutoff;

  double? _lastTimestampSeconds;
  double? _lastRawValue;
  double? _lastFilteredValue;
  double _lastFilteredDerivative = 0;

  double filter(double value, {double? timestampSeconds}) {
    final timestamp =
        timestampSeconds ??
        DateTime.now().microsecondsSinceEpoch / Duration.microsecondsPerSecond;
    final previousTimestamp = _lastTimestampSeconds;
    final previousRaw = _lastRawValue;
    final previousFiltered = _lastFilteredValue;

    if (previousTimestamp == null ||
        previousRaw == null ||
        previousFiltered == null ||
        timestamp <= previousTimestamp) {
      _lastTimestampSeconds = timestamp;
      _lastRawValue = value;
      _lastFilteredValue = value;
      _lastFilteredDerivative = 0;
      return value;
    }

    final deltaSeconds = (timestamp - previousTimestamp).clamp(0.001, 10.0);
    final frequency = 1.0 / deltaSeconds;
    final derivative = (value - previousRaw) * frequency;
    final derivativeAlpha = _alpha(derivativeCutoff, frequency);
    final filteredDerivative =
        derivativeAlpha * derivative +
        (1 - derivativeAlpha) * _lastFilteredDerivative;
    final cutoff = minCutoff + beta * filteredDerivative.abs();
    final valueAlpha = _alpha(cutoff, frequency);
    final filtered = valueAlpha * value + (1 - valueAlpha) * previousFiltered;

    _lastTimestampSeconds = timestamp;
    _lastRawValue = value;
    _lastFilteredValue = filtered;
    _lastFilteredDerivative = filteredDerivative;
    return filtered;
  }

  double _alpha(double cutoff, double frequency) {
    final safeCutoff = math.max(cutoff, 0.0001);
    return 1.0 / (1.0 + frequency / (2 * math.pi * safeCutoff));
  }

  void reset() {
    _lastTimestampSeconds = null;
    _lastRawValue = null;
    _lastFilteredValue = null;
    _lastFilteredDerivative = 0;
  }
}
