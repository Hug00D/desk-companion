import '../vision/companion_state_evaluator.dart';

enum ReminderPolicyResponse { continueFocus, rest, remindLater, dismissed }

class ReminderPolicyPrompt {
  const ReminderPolicyPrompt({
    required this.status,
    required this.cause,
    required this.evidenceDuration,
  });

  final CompanionStatus status;
  final CompanionCause cause;
  final Duration evidenceDuration;
}

/// Conservative, user-confirmed reminder policy used by the real-app pilot.
///
/// Vision remains responsible for observable states. This policy only decides
/// whether an observation is strong and persistent enough to interrupt the
/// user, and never treats a reminder as proof that the user was asleep.
class ReminderPolicy {
  ReminderPolicy({
    this.continueCooldown = const Duration(minutes: 10),
    this.remindLaterCooldown = const Duration(minutes: 5),
    this.dismissedCooldown = const Duration(minutes: 15),
  });

  static const Duration fatiguePromptThreshold = Duration(seconds: 3);
  static const Duration drowsyPromptThreshold = Duration(seconds: 3);
  static const Duration postureDownPromptThreshold = Duration(seconds: 8);
  static const Duration distractedPromptThreshold = Duration(seconds: 15);

  final Duration continueCooldown;
  final Duration remindLaterCooldown;
  final Duration dismissedCooldown;

  final Map<_ReminderKey, _ReminderGate> _gates =
      <_ReminderKey, _ReminderGate>{};

  ReminderPolicyPrompt? evaluate({
    required CompanionStatus status,
    required CompanionCause cause,
    required Duration evidenceDuration,
    required DateTime now,
  }) {
    final threshold = thresholdFor(status, cause);
    if (threshold == null || evidenceDuration < threshold) return null;

    final key = _ReminderKey(status, cause);
    final gate = _gates.putIfAbsent(key, _ReminderGate.new);
    if (gate.promptedInEpisode || gate.requiresRecovery) return null;
    final blockedUntil = gate.blockedUntil;
    if (blockedUntil != null && now.isBefore(blockedUntil)) return null;

    gate.promptedInEpisode = true;
    return ReminderPolicyPrompt(
      status: status,
      cause: cause,
      evidenceDuration: evidenceDuration,
    );
  }

  Duration? thresholdFor(CompanionStatus status, CompanionCause cause) {
    switch (status) {
      case CompanionStatus.fatigue:
        return fatiguePromptThreshold;
      case CompanionStatus.distracted:
        return distractedPromptThreshold;
      case CompanionStatus.sleeping:
        return cause == CompanionCause.postureDown
            ? postureDownPromptThreshold
            : drowsyPromptThreshold;
      case CompanionStatus.normal:
      case CompanionStatus.attention:
      case CompanionStatus.userMissing:
        return null;
    }
  }

  void recordResponse({
    required CompanionStatus status,
    required CompanionCause cause,
    required ReminderPolicyResponse response,
    required DateTime now,
  }) {
    final gate = _gates.putIfAbsent(
      _ReminderKey(status, cause),
      _ReminderGate.new,
    );
    switch (response) {
      case ReminderPolicyResponse.continueFocus:
        gate.blockedUntil = now.add(continueCooldown);
        gate.requiresRecovery = true;
        break;
      case ReminderPolicyResponse.rest:
        gate.requiresRecovery = true;
        break;
      case ReminderPolicyResponse.remindLater:
        gate.blockedUntil = now.add(remindLaterCooldown);
        gate.promptedInEpisode = false;
        gate.requiresRecovery = false;
        break;
      case ReminderPolicyResponse.dismissed:
        gate.blockedUntil = now.add(dismissedCooldown);
        gate.requiresRecovery = true;
        break;
    }
  }

  /// Re-arms a cause only after its evidence episode has actually ended.
  /// Cooldown still applies if a new episode begins immediately afterward.
  void markEpisodeEnded(CompanionStatus status, CompanionCause cause) {
    final gate = _gates[_ReminderKey(status, cause)];
    if (gate == null) return;
    gate.promptedInEpisode = false;
    gate.requiresRecovery = false;
  }

  void reset() => _gates.clear();
}

class _ReminderKey {
  const _ReminderKey(this.status, this.cause);

  final CompanionStatus status;
  final CompanionCause cause;

  @override
  bool operator ==(Object other) {
    return other is _ReminderKey &&
        other.status == status &&
        other.cause == cause;
  }

  @override
  int get hashCode => Object.hash(status, cause);
}

class _ReminderGate {
  bool promptedInEpisode = false;
  bool requiresRecovery = false;
  DateTime? blockedUntil;
}
