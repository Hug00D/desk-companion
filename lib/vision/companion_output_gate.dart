import 'companion_state_evaluator.dart';

class CompanionOutputGateResult {
  const CompanionOutputGateResult({
    required this.status,
    required this.rawStatus,
    required this.changed,
    required this.isPending,
    required this.pendingDuration,
    required this.requiredDuration,
  });

  final CompanionStatus status;
  final CompanionStatus rawStatus;
  final bool changed;
  final bool isPending;
  final Duration pendingDuration;
  final Duration requiredDuration;
}

class CompanionOutputGate {
  CompanionOutputGate({Map<CompanionStatus, Duration>? minimumDurations})
    : _minimumDurations = minimumDurations ?? _defaultMinimumDurations;

  static const Map<CompanionStatus, Duration> _defaultMinimumDurations =
      <CompanionStatus, Duration>{
        CompanionStatus.normal: Duration(milliseconds: 1600),
        CompanionStatus.attention: Duration(seconds: 3),
        CompanionStatus.fatigue: Duration(milliseconds: 2400),
        CompanionStatus.distracted: Duration(seconds: 4),
        CompanionStatus.drowsy: Duration(seconds: 3),
        CompanionStatus.postureDown: Duration(seconds: 4),
        CompanionStatus.userMissing: Duration(seconds: 8),
      };

  final Map<CompanionStatus, Duration> _minimumDurations;

  CompanionStatus _currentStatus = CompanionStatus.normal;
  CompanionStatus? _candidateStatus;
  DateTime? _candidateSince;

  CompanionStatus get currentStatus => _currentStatus;

  CompanionOutputGateResult evaluate(
    CompanionStatus rawStatus, {
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();
    if (rawStatus == _currentStatus) {
      _candidateStatus = null;
      _candidateSince = null;
      return CompanionOutputGateResult(
        status: _currentStatus,
        rawStatus: rawStatus,
        changed: false,
        isPending: false,
        pendingDuration: Duration.zero,
        requiredDuration: _durationFor(rawStatus),
      );
    }

    if (_candidateStatus != rawStatus) {
      _candidateStatus = rawStatus;
      _candidateSince = timestamp;
    }

    final since = _candidateSince ?? timestamp;
    final pendingDuration = timestamp.difference(since);
    final requiredDuration = _durationFor(rawStatus);
    if (pendingDuration >= requiredDuration) {
      final changed = _currentStatus != rawStatus;
      _currentStatus = rawStatus;
      _candidateStatus = null;
      _candidateSince = null;
      return CompanionOutputGateResult(
        status: _currentStatus,
        rawStatus: rawStatus,
        changed: changed,
        isPending: false,
        pendingDuration: pendingDuration,
        requiredDuration: requiredDuration,
      );
    }

    return CompanionOutputGateResult(
      status: _currentStatus,
      rawStatus: rawStatus,
      changed: false,
      isPending: true,
      pendingDuration: pendingDuration,
      requiredDuration: requiredDuration,
    );
  }

  void reset() {
    _currentStatus = CompanionStatus.normal;
    _candidateStatus = null;
    _candidateSince = null;
  }

  Duration _durationFor(CompanionStatus status) {
    return _minimumDurations[status] ?? const Duration(seconds: 3);
  }
}
