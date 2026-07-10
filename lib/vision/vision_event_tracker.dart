import 'companion_state_evaluator.dart';
import 'vision_event.dart';

class VisionEventTrackingResult {
  const VisionEventTrackingResult({
    required this.event,
    required this.isStable,
    required this.shouldUpdateMessage,
    required this.shouldNotify,
    required this.shouldPersist,
    required this.consecutiveFrames,
    required this.consecutiveDuration,
  });

  final VisionEvent event;
  final bool isStable;
  final bool shouldUpdateMessage;
  final bool shouldNotify;
  final bool shouldPersist;
  final int consecutiveFrames;
  final Duration consecutiveDuration;
}

class VisionEventTracker {
  VisionEventTracker({
    this.normalStableFrames = 5,
    this.partialUserStableFrames = 10,
    this.userAwayStableFrames = 15,
    this.attentionStableFrames = 4,
    this.fatigueStableFrames = 2,
    this.distractedStableFrames = 4,
    this.drowsyStableFrames = 3,
    this.postureDownStableFrames = 4,
    this.attentionPersistCooldown = const Duration(seconds: 15),
    this.partialUserPersistCooldown = const Duration(seconds: 20),
    this.userAwayPersistCooldown = const Duration(seconds: 30),
    this.fatigueNotifyCooldown = const Duration(seconds: 20),
    this.fatiguePersistCooldown = const Duration(seconds: 20),
    this.distractedPersistCooldown = const Duration(seconds: 20),
    this.drowsyPersistCooldown = const Duration(seconds: 20),
    this.postureDownPersistCooldown = const Duration(seconds: 30),
    this.userReturnedPersistCooldown = const Duration(seconds: 10),
  });

  final int normalStableFrames;
  final int partialUserStableFrames;
  final int userAwayStableFrames;
  final int attentionStableFrames;
  final int fatigueStableFrames;
  final int distractedStableFrames;
  final int drowsyStableFrames;
  final int postureDownStableFrames;
  final Duration attentionPersistCooldown;
  final Duration partialUserPersistCooldown;
  final Duration userAwayPersistCooldown;
  final Duration fatigueNotifyCooldown;
  final Duration fatiguePersistCooldown;
  final Duration distractedPersistCooldown;
  final Duration drowsyPersistCooldown;
  final Duration postureDownPersistCooldown;
  final Duration userReturnedPersistCooldown;

  VisionEventType? _candidateType;
  DateTime? _candidateStartedAt;
  int _candidateFrames = 0;
  VisionEventType _stableType = VisionEventType.normal;
  final Map<VisionEventType, DateTime> _lastNotifyAt = {};
  final Map<VisionEventType, DateTime> _lastPersistAt = {};

  VisionEventTrackingResult track(
    CompanionAnalysis analysis, {
    DateTime? now,
    String? actionTriggered,
  }) {
    final timestamp = now ?? DateTime.now();
    final rawEvent = VisionEvent.fromAnalysis(
      analysis,
      timestamp: timestamp,
      actionTriggered: actionTriggered,
    );
    final rawType = rawEvent.type;

    if (_candidateType != rawType) {
      _candidateType = rawType;
      _candidateStartedAt = timestamp;
      _candidateFrames = 1;
    } else {
      _candidateFrames += 1;
    }

    final stableEnough = _candidateFrames >= _stableFrameThreshold(rawType);
    final previousStableType = _stableType;
    var eventType = rawType;

    if (stableEnough) {
      _stableType = rawType;
      if (rawType == VisionEventType.normal &&
          previousStableType != VisionEventType.normal) {
        eventType = VisionEventType.userReturned;
      }
    }

    final event = eventType == rawType
        ? rawEvent
        : VisionEvent.fromAnalysis(
            analysis,
            timestamp: timestamp,
            typeOverride: eventType,
            actionTriggered: actionTriggered,
          );
    final consecutiveDuration = timestamp.difference(
      _candidateStartedAt ?? timestamp,
    );

    final shouldUpdateMessage =
        stableEnough &&
        (eventType != VisionEventType.normal ||
            previousStableType != VisionEventType.normal ||
            _stableType == VisionEventType.normal);
    final shouldNotify = stableEnough && _shouldNotify(eventType, timestamp);
    final shouldPersist = stableEnough && _shouldPersist(event, timestamp);

    return VisionEventTrackingResult(
      event: event,
      isStable: stableEnough,
      shouldUpdateMessage: shouldUpdateMessage,
      shouldNotify: shouldNotify,
      shouldPersist: shouldPersist,
      consecutiveFrames: _candidateFrames,
      consecutiveDuration: consecutiveDuration,
    );
  }

  void reset() {
    _candidateType = null;
    _candidateStartedAt = null;
    _candidateFrames = 0;
    _stableType = VisionEventType.normal;
    _lastNotifyAt.clear();
    _lastPersistAt.clear();
  }

  int _stableFrameThreshold(VisionEventType type) {
    switch (type) {
      case VisionEventType.partialUserDetected:
        return partialUserStableFrames;
      case VisionEventType.userAway:
        return userAwayStableFrames;
      case VisionEventType.attentionWarning:
        return attentionStableFrames;
      case VisionEventType.fatigueDetected:
        return fatigueStableFrames;
      case VisionEventType.distracted:
        return distractedStableFrames;
      case VisionEventType.drowsyDetected:
        return drowsyStableFrames;
      case VisionEventType.postureDownDetected:
        return postureDownStableFrames;
      case VisionEventType.userReturned:
      case VisionEventType.normal:
        return normalStableFrames;
    }
  }

  bool _shouldNotify(VisionEventType type, DateTime now) {
    if (type != VisionEventType.fatigueDetected) return false;
    if (!_cooldownReady(_lastNotifyAt[type], now, fatigueNotifyCooldown)) {
      return false;
    }
    _lastNotifyAt[type] = now;
    return true;
  }

  bool _shouldPersist(VisionEvent event, DateTime now) {
    if (!event.shouldPersist) return false;
    final cooldown = _persistCooldownFor(event.type);
    if (!_cooldownReady(_lastPersistAt[event.type], now, cooldown)) {
      return false;
    }
    _lastPersistAt[event.type] = now;
    return true;
  }

  Duration _persistCooldownFor(VisionEventType type) {
    switch (type) {
      case VisionEventType.attentionWarning:
        return attentionPersistCooldown;
      case VisionEventType.partialUserDetected:
        return partialUserPersistCooldown;
      case VisionEventType.userAway:
        return userAwayPersistCooldown;
      case VisionEventType.fatigueDetected:
        return fatiguePersistCooldown;
      case VisionEventType.distracted:
        return distractedPersistCooldown;
      case VisionEventType.drowsyDetected:
        return drowsyPersistCooldown;
      case VisionEventType.postureDownDetected:
        return postureDownPersistCooldown;
      case VisionEventType.userReturned:
        return userReturnedPersistCooldown;
      case VisionEventType.normal:
        return Duration.zero;
    }
  }

  bool _cooldownReady(DateTime? lastTime, DateTime now, Duration cooldown) {
    if (lastTime == null) return true;
    return now.difference(lastTime) >= cooldown;
  }
}
