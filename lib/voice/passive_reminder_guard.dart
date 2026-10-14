import '../vision/companion_state_evaluator.dart';

/// Defers passive audio during transitions without changing vision labels.
class PassiveReminderGuard {
  PassiveReminderGuard({
    this.observationDuration = const Duration(milliseconds: 800),
    this.maximumSampleGap = const Duration(seconds: 3),
  });

  final Duration observationDuration;
  final Duration maximumSampleGap;

  int _revision = 0;
  CompanionStatus? _status;
  CompanionCause? _cause;
  DateTime? _observedAt;
  DateTime? _holdUntil;
  bool _hasFace = false;
  bool _hasPose = false;
  bool _motionSuspected = false;

  int get revision => _revision;

  void observe({
    required CompanionStatus status,
    required CompanionCause cause,
    required bool hasFace,
    required bool hasPose,
    required bool motionSuspected,
    required DateTime now,
  }) {
    final previousAt = _observedAt;
    if (previousAt != null &&
        (now.isBefore(previousAt) ||
            now.difference(previousAt) > maximumSampleGap)) {
      reset();
    }
    final changed = _status != status || _cause != cause;
    final faceLost = _hasFace && !hasFace;
    final fullyLost = (_hasFace || _hasPose) && !hasFace && !hasPose;
    if (changed || fullyLost) _revision++;

    final newMotionState =
        changed &&
        (status == CompanionStatus.distracted ||
            status == CompanionStatus.sleeping);
    if (faceLost ||
        fullyLost ||
        newMotionState ||
        (motionSuspected && !_motionSuspected)) {
      _holdUntil = now.add(observationDuration);
    }
    _status = status;
    _cause = cause;
    _hasFace = hasFace;
    _hasPose = hasPose;
    _motionSuspected = motionSuspected;
    _observedAt = now;
  }

  bool isCurrent(CompanionStatus status, CompanionCause cause, int revision) =>
      revision == _revision &&
      _status == status &&
      _cause == cause &&
      status != CompanionStatus.normal &&
      status != CompanionStatus.userMissing;

  bool canPlay(
    CompanionStatus status,
    CompanionCause cause,
    int revision, {
    required DateTime now,
  }) {
    if (!isCurrent(status, cause, revision)) return false;
    final observedAt = _observedAt;
    if (observedAt == null ||
        now.isBefore(observedAt) ||
        now.difference(observedAt) > maximumSampleGap ||
        (!_hasFace && !_hasPose)) {
      return false;
    }
    // Require a new observation to confirm the transition has settled.
    return _holdUntil == null || !observedAt.isBefore(_holdUntil!);
  }

  void reset() {
    _revision++;
    _status = null;
    _cause = null;
    _observedAt = null;
    _holdUntil = null;
    _hasFace = false;
    _hasPose = false;
    _motionSuspected = false;
  }
}

/// Active conversation audio omits [canStart] and keeps its existing behavior.
Future<bool> startVoicePlaybackIfEligible({
  required Future<void> ready,
  required Future<void> Function() prepare,
  required Future<void> Function() start,
  bool Function()? canStart,
}) async {
  await ready;
  if (canStart != null && !canStart()) return false;
  await prepare();
  if (canStart != null && !canStart()) return false;
  await start();
  return true;
}
