import 'vision_result.dart';

enum DisappearanceState { none, pending, away, sleepCandidate, unknown }

class DisappearanceContextResult {
  const DisappearanceContextResult({
    required this.state,
    required this.reason,
    required this.faceMissingMs,
    required this.reliableHistory,
    required this.sideExit,
    required this.relativeDescent,
    required this.sleepSupported,
  });

  final DisappearanceState state;
  final String reason;
  final int faceMissingMs;
  final bool reliableHistory;
  final bool sideExit;
  final bool relativeDescent;
  final bool sleepSupported;
}

/// Experimental disappearance arbitration; missing data is never a descent.
class DisappearanceContextClassifier {
  DisappearanceContextClassifier({this.maximumGapMs = defaultMaximumGapMs})
    : assert(maximumGapMs > 0);

  static const historyMs = 1000;
  static const minimumHistoryMs = 300;
  static const confirmationMs = 500;
  static const recoveryMs = 500;
  static const defaultMaximumGapMs = 500;
  static const relativeDescentThreshold = 0.06;
  static const edgeMargin = 0.15;
  static const lateralHeadTravel = 0.20;
  static const lateralBodyTravel = 0.15;

  final int maximumGapMs;

  final List<_VisibleSample> _history = [];
  int? _lastTimestamp;
  int? _missingSince;
  int? _fullyMissingSince;
  int? _returnSince;
  int? _lastReliableBodyAt;
  bool _reliableHistory = false;
  bool _sideExit = false;
  bool _relativeDescent = false;
  bool _away = false;
  bool _postureConfirmed = false;
  bool _lowHeadBeforeLoss = false;

  DisappearanceContextResult classify({
    required int timestampMs,
    required VisionResult result,
    required bool reliablePose,
    required bool confirmedSleepPosture,
    bool matureLowHeadBeforeLoss = false,
  }) {
    if (timestampMs < 0 ||
        (_lastTimestamp != null && timestampMs <= _lastTimestamp!)) {
      throw ArgumentError('Disappearance timestamps must increase.');
    }
    if (_lastTimestamp != null &&
        timestampMs - _lastTimestamp! > maximumGapMs) {
      reset();
    }
    _lastTimestamp = timestampMs;

    if (result.hasFace) {
      if (_missingSince != null) {
        // A face returning does not need to be upright to prove presence.
        _returnSince ??= timestampMs;
        if (timestampMs - _returnSince! < recoveryMs) {
          return _result(
            _away ? DisappearanceState.away : DisappearanceState.unknown,
            'confirming_return',
            timestampMs,
          );
        }
        _clearLoss();
        _history.clear();
      }
      if (reliablePose) {
        _history.add(
          _VisibleSample(
            ms: timestampMs,
            noseX: result.poseNoseX! / result.imageWidth!,
            shoulderX:
                (result.leftShoulderX! + result.rightShoulderX!) /
                (2 * result.imageWidth!),
            headRelativeY:
                (result.poseNoseY! - result.shoulderCenterY!) /
                result.imageHeight!,
          ),
        );
      }
      _history.removeWhere((sample) => timestampMs - sample.ms > historyMs);
      return _result(DisappearanceState.none, 'face_visible', timestampMs);
    }

    _returnSince = null;
    if (_missingSince == null) {
      _missingSince = timestampMs;
      _lowHeadBeforeLoss = matureLowHeadBeforeLoss;
      _history.removeWhere((sample) => timestampMs - sample.ms > historyMs);
      if (_history.length >= 2) {
        final last = _history.last;
        _reliableHistory =
            timestampMs - last.ms <= maximumGapMs &&
            last.ms - _history.first.ms >= minimumHistoryMs;
        if (_reliableHistory) {
          for (final previous in _history) {
            if (last.headRelativeY - previous.headRelativeY >=
                relativeDescentThreshold) {
              _relativeDescent = true;
            }
            final leftExit =
                last.noseX <= edgeMargin &&
                previous.noseX - last.noseX >= lateralHeadTravel &&
                previous.shoulderX - last.shoulderX >= lateralBodyTravel;
            final rightExit =
                last.noseX >= 1 - edgeMargin &&
                last.noseX - previous.noseX >= lateralHeadTravel &&
                last.shoulderX - previous.shoulderX >= lateralBodyTravel;
            _sideExit = _sideExit || leftExit || rightExit;
          }
        }
      }
      // Freeze only visible-user history. Pose after loss may be the chair.
      _history.clear();
    }
    if (!result.hasPose) {
      _fullyMissingSince ??= timestampMs;
    } else {
      _fullyMissingSince = null;
    }
    if (reliablePose) {
      _lastReliableBodyAt = timestampMs;
      _postureConfirmed = _postureConfirmed || confirmedSleepPosture;
    }
    if (_away) {
      return _result(DisappearanceState.away, 'away_latched', timestampMs);
    }
    if (timestampMs - _missingSince! < confirmationMs) {
      return _result(
        DisappearanceState.pending,
        'confirming_loss',
        timestampMs,
      );
    }
    final fullyAbsent =
        _fullyMissingSince != null &&
        timestampMs - _fullyMissingSince! >= confirmationMs;
    if (_sideExit ||
        (_reliableHistory &&
            !_relativeDescent &&
            fullyAbsent &&
            !_lowHeadBeforeLoss)) {
      _away = true;
      return _result(
        DisappearanceState.away,
        _sideExit ? 'head_and_body_side_exit' : 'fully_absent_without_descent',
        timestampMs,
      );
    }
    if (_relativeDescent) {
      return _result(
        DisappearanceState.sleepCandidate,
        'relative_head_descent',
        timestampMs,
      );
    }
    if (_lowHeadBeforeLoss && fullyAbsent) {
      return _result(
        DisappearanceState.unknown,
        'low_head_tracking_lost',
        timestampMs,
      );
    }
    return _result(
      DisappearanceState.unknown,
      'insufficient_exit_evidence',
      timestampMs,
    );
  }

  DisappearanceContextResult _result(
    DisappearanceState state,
    String reason,
    int ms,
  ) => DisappearanceContextResult(
    state: state,
    reason: reason,
    faceMissingMs: _missingSince == null ? 0 : ms - _missingSince!,
    reliableHistory: _reliableHistory,
    sideExit: _sideExit,
    relativeDescent: _relativeDescent,
    sleepSupported:
        _relativeDescent &&
        _postureConfirmed &&
        _lastReliableBodyAt != null &&
        ms - _lastReliableBodyAt! <= maximumGapMs,
  );

  void _clearLoss() {
    _missingSince = null;
    _fullyMissingSince = null;
    _returnSince = null;
    _lastReliableBodyAt = null;
    _reliableHistory = false;
    _sideExit = false;
    _relativeDescent = false;
    _away = false;
    _postureConfirmed = false;
    _lowHeadBeforeLoss = false;
  }

  void reset() {
    _history.clear();
    _lastTimestamp = null;
    _clearLoss();
  }
}

class _VisibleSample {
  const _VisibleSample({
    required this.ms,
    required this.noseX,
    required this.shoulderX,
    required this.headRelativeY,
  });

  final int ms;
  final double noseX;
  final double shoulderX;
  final double headRelativeY;
}
