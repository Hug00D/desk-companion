import 'package:flutter/foundation.dart';

import '../vision/companion_state_evaluator.dart';
import 'focus_session_report.dart';
import 'reminder_policy.dart';

enum FocusInterventionType {
  reminder,
  checkIn,
  eventRecorded,
  offerPause,
  autoPause,
  recovered,
}

class FocusIntervention {
  const FocusIntervention({
    required this.type,
    required this.status,
    required this.cause,
    required this.episodeDuration,
  });

  final FocusInterventionType type;
  final CompanionStatus status;
  final CompanionCause cause;
  final Duration episodeDuration;
}

class FocusSessionMonitor extends ChangeNotifier {
  FocusSessionMonitor._() : reminderPolicy = ReminderPolicy();

  FocusSessionMonitor.detached({ReminderPolicy? reminderPolicy})
    : reminderPolicy = reminderPolicy ?? ReminderPolicy();

  static final FocusSessionMonitor instance = FocusSessionMonitor._();

  factory FocusSessionMonitor() => instance;

  static const Duration evidenceGraceDuration = Duration(seconds: 3);
  static const Duration recoveryDuration = Duration(seconds: 3);
  static const Duration reminderThreshold = Duration(seconds: 3);
  static const Duration eventThreshold = Duration(seconds: 5);
  static const Duration maximumSampleGap = Duration(seconds: 3);

  final ReminderPolicy reminderPolicy;

  final Map<CompanionStatus, _StatusEvidence> _evidenceByStatus =
      <CompanionStatus, _StatusEvidence>{};
  final Map<CompanionStatus, int> _eventCounts = <CompanionStatus, int>{};
  final Map<CompanionCause, int> _causeEventCounts = <CompanionCause, int>{};

  CompanionStatus _lastObservedStatus = CompanionStatus.normal;
  CompanionCause _lastObservedCause = CompanionCause.none;
  CompanionStatus? _activeEpisodeStatus;
  CompanionStatus? _autoPausedStatus;
  DateTime? _lastSampleAt;
  DateTime? _normalStartedAt;
  bool _recoveryPromptDelivered = false;

  Duration effectiveFocusDuration = Duration.zero;
  Duration distractedDuration = Duration.zero;
  FocusSessionReport? lastCompletedReport;

  bool severeAutoPauseEnabled = true;
  bool longDistractionAutoPauseEnabled = false;
  bool experimentalReminderPolicyEnabled = false;

  CompanionStatus? get activeEpisodeStatus => _activeEpisodeStatus;

  int eventCountFor(CompanionStatus status) => _eventCounts[status] ?? 0;

  int causeEventCountFor(CompanionCause cause) => _causeEventCounts[cause] ?? 0;

  int get totalEventCount =>
      _eventCounts.values.fold<int>(0, (total, count) => total + count);

  void beginSession({DateTime? now}) {
    effectiveFocusDuration = Duration.zero;
    distractedDuration = Duration.zero;
    _eventCounts.clear();
    _causeEventCounts.clear();
    lastCompletedReport = null;
    _lastSampleAt = now ?? DateTime.now();
    _clearAllState();
    notifyListeners();
  }

  FocusSessionReport completeSession({
    required Duration plannedDuration,
    DateTime? now,
  }) {
    final report = FocusSessionReport(
      completedAt: now ?? DateTime.now(),
      plannedDuration: plannedDuration,
      effectiveFocusDuration: effectiveFocusDuration,
      distractedDuration: distractedDuration,
      eventCounts: <CompanionStatus, int>{
        for (final status in CompanionStatus.values)
          if (eventCountFor(status) > 0) status: eventCountFor(status),
      },
      causeEventCounts: <CompanionCause, int>{
        for (final cause in CompanionCause.values)
          if (causeEventCountFor(cause) > 0) cause: causeEventCountFor(cause),
      },
    );
    lastCompletedReport = report;
    _lastSampleAt = null;
    _clearAllState();
    notifyListeners();
    return report;
  }

  void endSession() {
    _lastSampleAt = null;
    _clearAllState();
    notifyListeners();
  }

  void resetDetectionState({DateTime? now}) {
    _lastSampleAt = now ?? DateTime.now();
    _clearAllState();
    notifyListeners();
  }

  void setSevereAutoPauseEnabled(bool enabled) {
    if (severeAutoPauseEnabled == enabled) return;
    severeAutoPauseEnabled = enabled;
    notifyListeners();
  }

  void setLongDistractionAutoPauseEnabled(bool enabled) {
    if (longDistractionAutoPauseEnabled == enabled) return;
    longDistractionAutoPauseEnabled = enabled;
    notifyListeners();
  }

  void setExperimentalReminderPolicyEnabled(bool enabled) {
    if (experimentalReminderPolicyEnabled == enabled) return;
    experimentalReminderPolicyEnabled = enabled;
    reminderPolicy.reset();
    _resetEvidence();
    notifyListeners();
  }

  void recordReminderResponse({
    required CompanionStatus status,
    required CompanionCause cause,
    required ReminderPolicyResponse response,
    DateTime? now,
  }) {
    reminderPolicy.recordResponse(
      status: status,
      cause: cause,
      response: response,
      now: now ?? DateTime.now(),
    );
    notifyListeners();
  }

  List<FocusIntervention> update({
    required CompanionStatus status,
    required CompanionCause cause,
    required bool sessionActive,
    required bool sessionRunning,
    required bool sessionAutoPaused,
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();
    final shouldCollectEvidence = !sessionActive || sessionRunning;
    _accumulateElapsed(
      timestamp: timestamp,
      sessionRunning: sessionRunning,
      shouldCollectEvidence: shouldCollectEvidence,
    );
    _lastObservedStatus = status;
    _lastObservedCause = cause;

    if (sessionAutoPaused) {
      final interventions = _handleAutoPausedStatus(status, cause, timestamp);
      notifyListeners();
      return interventions;
    }

    if (sessionActive && !sessionRunning) {
      _resetEvidence();
      notifyListeners();
      return const <FocusIntervention>[];
    }

    if (sessionRunning &&
        (_autoPausedStatus != null || _recoveryPromptDelivered)) {
      _clearAllState();
      _lastSampleAt = timestamp;
      _lastObservedStatus = status;
      _lastObservedCause = cause;
      _touchCurrentStatus(status, cause, timestamp);
      _updateActiveStatus(status);
      notifyListeners();
      return const <FocusIntervention>[];
    }

    _normalStartedAt = null;
    _touchCurrentStatus(status, cause, timestamp);
    _expireStaleEvidence(timestamp);
    _updateActiveStatus(status);

    final interventions = _evaluateEvidence(
      currentStatus: status,
      currentCause: cause,
      sessionRunning: sessionRunning,
    );
    notifyListeners();
    return interventions;
  }

  void _accumulateElapsed({
    required DateTime timestamp,
    required bool sessionRunning,
    required bool shouldCollectEvidence,
  }) {
    final previousSampleAt = _lastSampleAt;
    _lastSampleAt = timestamp;
    if (previousSampleAt == null) return;

    final delta = timestamp.difference(previousSampleAt);
    if (delta <= Duration.zero || delta > maximumSampleGap) return;

    if (shouldCollectEvidence &&
        _lastObservedStatus != CompanionStatus.normal) {
      final evidence = _evidenceByStatus.putIfAbsent(
        _lastObservedStatus,
        () => _StatusEvidence(
          seenAt: previousSampleAt,
          cause: _lastObservedCause,
        ),
      );
      evidence.cause = _lastObservedCause;
      evidence.accumulated += delta;
      evidence.lastSeenAt = timestamp;
    }

    if (!sessionRunning) return;
    if (_lastObservedStatus == CompanionStatus.normal ||
        _lastObservedStatus == CompanionStatus.attention) {
      effectiveFocusDuration += delta;
    } else {
      distractedDuration += delta;
    }
  }

  void _touchCurrentStatus(
    CompanionStatus status,
    CompanionCause cause,
    DateTime timestamp,
  ) {
    if (status == CompanionStatus.normal) return;
    final evidence = _evidenceByStatus.putIfAbsent(
      status,
      () => _StatusEvidence(seenAt: timestamp, cause: cause),
    );
    evidence.cause = cause;
    evidence.lastSeenAt = timestamp;
  }

  void _expireStaleEvidence(DateTime timestamp) {
    final expired = _evidenceByStatus.entries
        .where(
          (entry) =>
              timestamp.difference(entry.value.lastSeenAt) >=
              evidenceGraceDuration,
        )
        .toList(growable: false);
    for (final entry in expired) {
      reminderPolicy.markEpisodeEnded(entry.key, entry.value.cause);
      _evidenceByStatus.remove(entry.key);
    }
  }

  void _updateActiveStatus(CompanionStatus currentStatus) {
    if (currentStatus != CompanionStatus.normal &&
        _evidenceByStatus.containsKey(currentStatus)) {
      _activeEpisodeStatus = currentStatus;
      return;
    }

    CompanionStatus? newestStatus;
    DateTime? newestSeenAt;
    for (final entry in _evidenceByStatus.entries) {
      if (newestSeenAt == null ||
          entry.value.lastSeenAt.isAfter(newestSeenAt)) {
        newestStatus = entry.key;
        newestSeenAt = entry.value.lastSeenAt;
      }
    }
    _activeEpisodeStatus = newestStatus;
  }

  List<FocusIntervention> _evaluateEvidence({
    required CompanionStatus currentStatus,
    required CompanionCause currentCause,
    required bool sessionRunning,
  }) {
    final interventions = <FocusIntervention>[];

    for (final entry in _evidenceByStatus.entries) {
      final status = entry.key;
      final evidence = entry.value;
      final isCurrentStatus = status == currentStatus;

      if (experimentalReminderPolicyEnabled && isCurrentStatus) {
        final prompt = reminderPolicy.evaluate(
          status: status,
          cause: evidence.cause,
          evidenceDuration: evidence.accumulated,
          now: evidence.lastSeenAt,
        );
        if (prompt != null) {
          interventions.add(
            FocusIntervention(
              type: FocusInterventionType.checkIn,
              status: prompt.status,
              cause: prompt.cause,
              episodeDuration: prompt.evidenceDuration,
            ),
          );
        }
      }

      if (!experimentalReminderPolicyEnabled &&
          isCurrentStatus &&
          !evidence.reminderSent &&
          status != CompanionStatus.userMissing &&
          evidence.accumulated >= _reminderThresholdFor(status)) {
        evidence.reminderSent = true;
        interventions.add(
          FocusIntervention(
            type: FocusInterventionType.reminder,
            status: status,
            cause: evidence.cause,
            episodeDuration: evidence.accumulated,
          ),
        );
      }

      if (sessionRunning &&
          !evidence.eventRecorded &&
          evidence.accumulated >= eventThreshold) {
        evidence.eventRecorded = true;
        _eventCounts[status] = eventCountFor(status) + 1;
        _causeEventCounts[evidence.cause] =
            causeEventCountFor(evidence.cause) + 1;
        interventions.add(
          FocusIntervention(
            type: FocusInterventionType.eventRecorded,
            status: status,
            cause: evidence.cause,
            episodeDuration: evidence.accumulated,
          ),
        );
      }

      if (!sessionRunning || !isCurrentStatus || evidence.pauseDecisionSent) {
        continue;
      }
      if (experimentalReminderPolicyEnabled) continue;
      final pauseIntervention = _pauseInterventionFor(
        status: status,
        cause: isCurrentStatus ? currentCause : evidence.cause,
        evidenceDuration: evidence.accumulated,
      );
      if (pauseIntervention == null) continue;

      evidence.pauseDecisionSent = true;
      if (pauseIntervention.type == FocusInterventionType.autoPause) {
        _autoPausedStatus = status;
        _recoveryPromptDelivered = false;
      }
      interventions.add(pauseIntervention);
    }

    return interventions;
  }

  Duration _reminderThresholdFor(CompanionStatus status) {
    switch (status) {
      case CompanionStatus.sleeping:
        return const Duration(seconds: 2);
      case CompanionStatus.normal:
      case CompanionStatus.attention:
      case CompanionStatus.fatigue:
      case CompanionStatus.distracted:
      case CompanionStatus.userMissing:
        return reminderThreshold;
    }
  }

  List<FocusIntervention> _handleAutoPausedStatus(
    CompanionStatus status,
    CompanionCause cause,
    DateTime timestamp,
  ) {
    if (_recoveryPromptDelivered) return const <FocusIntervention>[];
    if (status != CompanionStatus.normal) {
      _normalStartedAt = null;
      return const <FocusIntervention>[];
    }

    _normalStartedAt ??= timestamp;
    if (timestamp.difference(_normalStartedAt!) < recoveryDuration) {
      return const <FocusIntervention>[];
    }

    final recoveredStatus = _autoPausedStatus ?? CompanionStatus.normal;
    final recoveredEvidence = _evidenceByStatus[recoveredStatus];
    final episodeDuration = recoveredEvidence?.accumulated ?? Duration.zero;
    final recoveredCause = recoveredEvidence?.cause ?? cause;
    _resetEvidence();
    _autoPausedStatus = null;
    _recoveryPromptDelivered = true;
    return <FocusIntervention>[
      FocusIntervention(
        type: FocusInterventionType.recovered,
        status: recoveredStatus,
        cause: recoveredCause,
        episodeDuration: episodeDuration,
      ),
    ];
  }

  FocusIntervention? _pauseInterventionFor({
    required CompanionStatus status,
    required CompanionCause cause,
    required Duration evidenceDuration,
  }) {
    FocusInterventionType? type;
    Duration? threshold;

    switch (status) {
      case CompanionStatus.distracted:
        threshold = const Duration(seconds: 15);
        type = longDistractionAutoPauseEnabled
            ? FocusInterventionType.autoPause
            : FocusInterventionType.offerPause;
        break;
      case CompanionStatus.fatigue:
        threshold = const Duration(seconds: 10);
        type = FocusInterventionType.offerPause;
        break;
      case CompanionStatus.sleeping:
        threshold = const Duration(seconds: 8);
        type = severeAutoPauseEnabled
            ? FocusInterventionType.autoPause
            : FocusInterventionType.offerPause;
        break;
      case CompanionStatus.userMissing:
        threshold = const Duration(seconds: 10);
        type = severeAutoPauseEnabled
            ? FocusInterventionType.autoPause
            : FocusInterventionType.offerPause;
        break;
      case CompanionStatus.normal:
      case CompanionStatus.attention:
        return null;
    }

    if (evidenceDuration < threshold) return null;
    return FocusIntervention(
      type: type,
      status: status,
      cause: cause,
      episodeDuration: evidenceDuration,
    );
  }

  void _resetEvidence() {
    for (final entry in _evidenceByStatus.entries) {
      reminderPolicy.markEpisodeEnded(entry.key, entry.value.cause);
    }
    _evidenceByStatus.clear();
    _activeEpisodeStatus = null;
    _normalStartedAt = null;
    _lastObservedStatus = CompanionStatus.normal;
    _lastObservedCause = CompanionCause.none;
  }

  void _clearAllState() {
    _resetEvidence();
    reminderPolicy.reset();
    _autoPausedStatus = null;
    _recoveryPromptDelivered = false;
  }
}

class _StatusEvidence {
  _StatusEvidence({required DateTime seenAt, required this.cause})
    : lastSeenAt = seenAt;

  DateTime lastSeenAt;
  CompanionCause cause;
  Duration accumulated = Duration.zero;
  bool reminderSent = false;
  bool eventRecorded = false;
  bool pauseDecisionSent = false;
}
