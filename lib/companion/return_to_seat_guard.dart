import '../vision/companion_state_evaluator.dart';
import '../vision/dual_track_context_classifier.dart';
import '../vision/vision_result.dart';

enum ReturnToSeatPhase { inactive, awaitingReturn, standing, settling }

/// Fixed desk-camera guard, not a general sitting or identity classifier.
class ReturnToSeatGuard {
  ReturnToSeatGuard({
    this.settlingDuration = const Duration(milliseconds: 1500),
    this.maximumSampleGap = const Duration(milliseconds: 1500),
    this.minimumHipVisibility = 0.6,
    this.verticalTolerance = 0.06,
    this.horizontalTolerance = 0.10,
    this.widthTolerance = 0.30,
    this.motionTolerance = 0.015,
  });

  final Duration settlingDuration;
  final Duration maximumSampleGap;
  final double minimumHipVisibility;
  final double verticalTolerance;
  final double horizontalTolerance;
  final double widthTolerance;
  final double motionTolerance;
  static const baselineSamples = 5;

  final List<_SeatSample> _baselineSamples = [];
  _SeatSample? _baseline;
  _SeatSample? _previousCandidate;
  DateTime? _stableSince;
  DateTime? _lastFreshAt;
  bool _standingObserved = false;
  bool _hasReturnEvidence = false;
  ReturnToSeatPhase _phase = ReturnToSeatPhase.inactive;

  ReturnToSeatPhase get phase => _phase;
  bool get isAwaitingReturn => _phase != ReturnToSeatPhase.inactive;
  bool get hasReturnEvidence => _hasReturnEvidence;

  void beginReturn() {
    if (isAwaitingReturn) return;
    _phase = ReturnToSeatPhase.awaitingReturn;
    _standingObserved = false;
    _hasReturnEvidence = false;
    _lastFreshAt = null;
    _clearSettling();
  }

  void recordSeatedBaseline(
    CompanionAnalysis analysis, {
    required bool freshPose,
  }) {
    final result = analysis.visionResult;
    if (isAwaitingReturn ||
        !freshPose ||
        analysis.status != CompanionStatus.normal ||
        !result.hasFace ||
        !DualTrackContextClassifier.hasReliablePoseGeometry(result) ||
        (result.headPitch?.abs() ?? double.infinity) > 15 ||
        (result.headOffsetScore ?? double.infinity) > 30 ||
        (result.leftEyeOpen ?? 0) < 0.3 ||
        (result.rightEyeOpen ?? 0) < 0.3 ||
        (analysis.postureDownResult.score ?? 0) >= 35) {
      return;
    }
    final sample = _SeatSample.fromResult(result);
    if (_baseline != null && !_nearSeat(sample)) return;
    _baselineSamples.add(sample);
    if (_baselineSamples.length > baselineSamples) _baselineSamples.removeAt(0);
    if (_baselineSamples.length == baselineSamples) {
      _baseline = _SeatSample.median(_baselineSamples);
    }
  }

  bool suppressPosture(
    VisionResult result, {
    required bool freshPose,
    required DateTime now,
  }) {
    if (!isAwaitingReturn) return false;
    if (_lastFreshAt != null &&
        (now.isBefore(_lastFreshAt!) ||
            now.difference(_lastFreshAt!) > maximumSampleGap)) {
      _clearSettling();
    }
    if (!freshPose) return true;
    _lastFreshAt = now;
    if (!result.hasFace && !result.hasPose) {
      _clearSettling();
      _phase = ReturnToSeatPhase.awaitingReturn;
      return true;
    }

    final hips = _hipObservation(result);
    if (hips == _HipObservation.visible) {
      _standingObserved = true;
      _hasReturnEvidence = true;
      _phase = ReturnToSeatPhase.standing;
      _clearSettling();
      return true;
    }
    final reliablePose = DualTrackContextClassifier.hasReliablePoseGeometry(
      result,
    );
    if (result.hasFace || reliablePose) _hasReturnEvidence = true;
    // Missing hip fields are not proof that previously visible hips are hidden.
    if (!reliablePose ||
        (_standingObserved && hips == _HipObservation.unknown) ||
        (_baseline == null &&
            (hips != _HipObservation.hidden ||
                !result.hasFace ||
                (result.headPitch?.abs() ?? double.infinity) > 15))) {
      _clearSettling();
      return true;
    }
    final sample = _SeatSample.fromResult(result);
    if ((_baseline != null && !_nearSeat(sample)) ||
        (result.hasFace && (result.headPitch?.abs() ?? double.infinity) > 25)) {
      _clearSettling();
      return true;
    }
    final previous = _previousCandidate;
    if (previous == null ||
        (sample.noseY - previous.noseY).abs() > motionTolerance ||
        (sample.shoulderY - previous.shoulderY).abs() > motionTolerance ||
        (sample.shoulderX - previous.shoulderX).abs() > motionTolerance) {
      _stableSince = now;
      if (_baseline == null) _baselineSamples.clear();
    }
    _previousCandidate = sample;
    if (_baseline == null) {
      _baselineSamples.add(sample);
      if (_baselineSamples.length > baselineSamples) {
        _baselineSamples.removeAt(0);
      }
    }
    _phase = ReturnToSeatPhase.settling;
    if (now.difference(_stableSince!) < settlingDuration ||
        (_baseline == null && _baselineSamples.length < baselineSamples)) {
      return true;
    }

    _baseline ??= _SeatSample.median(_baselineSamples);

    _phase = ReturnToSeatPhase.inactive;
    _standingObserved = false;
    _clearSettling();
    return false;
  }

  bool _nearSeat(_SeatSample sample) {
    final baseline = _baseline!;
    return (sample.noseY - baseline.noseY).abs() <= verticalTolerance &&
        (sample.shoulderY - baseline.shoulderY).abs() <= verticalTolerance &&
        (sample.shoulderX - baseline.shoulderX).abs() <= horizontalTolerance &&
        (sample.noseX - baseline.noseX).abs() <= horizontalTolerance &&
        (sample.width / baseline.width - 1).abs() <= widthTolerance;
  }

  _HipObservation _hipObservation(VisionResult result) {
    final width = result.imageWidth;
    final height = result.imageHeight;
    if (!result.hasPose ||
        width == null ||
        height == null ||
        !width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0) {
      return _HipObservation.unknown;
    }
    bool known(double? x, double? y, double? visibility) =>
        x != null &&
        x.isFinite &&
        y != null &&
        y.isFinite &&
        visibility != null &&
        visibility.isFinite &&
        visibility >= 0 &&
        visibility <= 1;
    bool visible(double? x, double? y, double? visibility) =>
        known(x, y, visibility) &&
        visibility! >= minimumHipVisibility &&
        x! >= 0 &&
        x <= width &&
        y! >= 0 &&
        y <= height;
    if (visible(result.leftHipX, result.leftHipY, result.leftHipVisibility) ||
        visible(
          result.rightHipX,
          result.rightHipY,
          result.rightHipVisibility,
        )) {
      return _HipObservation.visible;
    }
    return known(result.leftHipX, result.leftHipY, result.leftHipVisibility) &&
            known(result.rightHipX, result.rightHipY, result.rightHipVisibility)
        ? _HipObservation.hidden
        : _HipObservation.unknown;
  }

  void _clearSettling() {
    if (_phase == ReturnToSeatPhase.settling) {
      _phase = ReturnToSeatPhase.awaitingReturn;
    }
    _stableSince = null;
    _previousCandidate = null;
    if (_baseline == null) _baselineSamples.clear();
  }

  void reset() {
    _baselineSamples.clear();
    _baseline = null;
    _phase = ReturnToSeatPhase.inactive;
    _standingObserved = false;
    _hasReturnEvidence = false;
    _lastFreshAt = null;
    _clearSettling();
  }
}

enum _HipObservation { unknown, visible, hidden }

class _SeatSample {
  const _SeatSample(
    this.noseX,
    this.noseY,
    this.shoulderX,
    this.shoulderY,
    this.width,
  );

  factory _SeatSample.fromResult(VisionResult result) => _SeatSample(
    result.poseNoseX! / result.imageWidth!,
    result.poseNoseY! / result.imageHeight!,
    (result.leftShoulderX! + result.rightShoulderX!) / (2 * result.imageWidth!),
    result.shoulderCenterY! / result.imageHeight!,
    (result.leftShoulderX! - result.rightShoulderX!).abs() / result.imageWidth!,
  );

  factory _SeatSample.median(List<_SeatSample> samples) {
    double median(double Function(_SeatSample) value) {
      final values = samples.map(value).toList()..sort();
      return values[values.length ~/ 2];
    }

    return _SeatSample(
      median((s) => s.noseX),
      median((s) => s.noseY),
      median((s) => s.shoulderX),
      median((s) => s.shoulderY),
      median((s) => s.width),
    );
  }

  final double noseX;
  final double noseY;
  final double shoulderX;
  final double shoulderY;
  final double width;
}
