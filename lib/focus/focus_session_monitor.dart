import 'package:flutter/foundation.dart';

import '../vision/companion_state_evaluator.dart';

enum FocusInterventionType {
  reminder,
  eventRecorded,
  offerPause,
  autoPause,
  recovered,
}

class FocusIntervention {
  const FocusIntervention({
    required this.type,
    required this.status,
    required this.episodeDuration,
  });

  final FocusInterventionType type;
  final CompanionStatus status;
  final Duration episodeDuration;
}

class FocusSessionMonitor extends ChangeNotifier {
  FocusSessionMonitor._();

  FocusSessionMonitor.detached();

  static final FocusSessionMonitor instance = FocusSessionMonitor._();

  factory FocusSessionMonitor() => instance;

  static const Duration evidenceGraceDuration = Duration(seconds: 3);
  static const Duration recoveryDuration = Duration(seconds: 3);
  static const Duration reminderThreshold = Duration(seconds: 3);
  static const Duration eventThreshold = Duration(seconds: 5);
  static const Duration maximumSampleGap = Duration(seconds: 3);

  final Map<CompanionStatus, _StatusEvidence> _evidenceByStatus =
      <CompanionStatus, _StatusEvidence>{};
  final Map<CompanionStatus, int> _eventCounts = <CompanionStatus, int>{};

  CompanionStatus _lastObservedStatus = CompanionStatus.normal;
  CompanionStatus? _activeEpisodeStatus;
  CompanionStatus? _autoPausedStatus;
  DateTime? _lastSampleAt;
  DateTime? _normalStartedAt;
  bool _recoveryPromptDelivered = false;

  Duration effectiveFocusDuration = Duration.zero;
  Duration distractedDuration = Duration.zero;

  bool severeAutoPauseEnabled = true;
  bool longDistractionAutoPauseEnabled = false;

  CompanionStatus? get activeEpisodeStatus => _activeEpisodeStatus;

  int eventCountFor(CompanionStatus status) => _eventCounts[status] ?? 0;

  int get totalEventCount =>
      _eventCounts.values.fold<int>(0, (total, count) => total + count);

  void beginSession({DateTime? now}) {
    effectiveFocusDuration = Duration.zero;
    distractedDuration = Duration.zero;
    _eventCounts.clear();
    _lastSampleAt = now ?? DateTime.now();
    _clearAllState();
    notifyListeners();
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

  List<FocusIntervention> update({
    required CompanionStatus status,
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

    if (sessionAutoPaused) {
      final interventions = _handleAutoPausedStatus(status, timestamp);
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
      _touchCurrentStatus(status, timestamp);
      _updateActiveStatus(status);
      notifyListeners();
      return const <FocusIntervention>[];
    }

    _normalStartedAt = null;
    _touchCurrentStatus(status, timestamp);
    _expireStaleEvidence(timestamp);
    _updateActiveStatus(status);

    final interventions = _evaluateEvidence(
      currentStatus: status,
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
        () => _StatusEvidence(seenAt: previousSampleAt),
      );
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

  void _touchCurrentStatus(CompanionStatus status, DateTime timestamp) {
    if (status == CompanionStatus.normal) return;
    final evidence = _evidenceByStatus.putIfAbsent(
      status,
      () => _StatusEvidence(seenAt: timestamp),
    );
    evidence.lastSeenAt = timestamp;
  }

  void _expireStaleEvidence(DateTime timestamp) {
    _evidenceByStatus.removeWhere((_, evidence) {
      return timestamp.difference(evidence.lastSeenAt) >= evidenceGraceDuration;
    });
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
    required bool sessionRunning,
  }) {
    final interventions = <FocusIntervention>[];

    for (final entry in _evidenceByStatus.entries) {
      final status = entry.key;
      final evidence = entry.value;
      final isCurrentStatus = status == currentStatus;

      if (isCurrentStatus &&
          !evidence.reminderSent &&
          status != CompanionStatus.userMissing &&
          evidence.accumulated >= _reminderThresholdFor(status)) {
        evidence.reminderSent = true;
        interventions.add(
          FocusIntervention(
            type: FocusInterventionType.reminder,
            status: status,
            episodeDuration: evidence.accumulated,
          ),
        );
      }

      if (sessionRunning &&
          !evidence.eventRecorded &&
          evidence.accumulated >= eventThreshold) {
        evidence.eventRecorded = true;
        _eventCounts[status] = eventCountFor(status) + 1;
        interventions.add(
          FocusIntervention(
            type: FocusInterventionType.eventRecorded,
            status: status,
            episodeDuration: evidence.accumulated,
          ),
        );
      }

      if (!sessionRunning || !isCurrentStatus || evidence.pauseDecisionSent) {
        continue;
      }
      final pauseIntervention = _pauseInterventionFor(
        status: status,
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
    final episodeDuration =
        _evidenceByStatus[recoveredStatus]?.accumulated ?? Duration.zero;
    _resetEvidence();
    _autoPausedStatus = null;
    _recoveryPromptDelivered = true;
    return <FocusIntervention>[
      FocusIntervention(
        type: FocusInterventionType.recovered,
        status: recoveredStatus,
        episodeDuration: episodeDuration,
      ),
    ];
  }

  FocusIntervention? _pauseInterventionFor({
    required CompanionStatus status,
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
      episodeDuration: evidenceDuration,
    );
  }

  void _resetEvidence() {
    _evidenceByStatus.clear();
    _activeEpisodeStatus = null;
    _normalStartedAt = null;
    _lastObservedStatus = CompanionStatus.normal;
  }

  void _clearAllState() {
    _resetEvidence();
    _autoPausedStatus = null;
    _recoveryPromptDelivered = false;
  }
}

class _StatusEvidence {
  _StatusEvidence({required DateTime seenAt}) : lastSeenAt = seenAt;

  DateTime lastSeenAt;
  Duration accumulated = Duration.zero;
  bool reminderSent = false;
  bool eventRecorded = false;
  bool pauseDecisionSent = false;
}
