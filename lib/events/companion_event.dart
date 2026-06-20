import 'dart:math';

enum CompanionEventSource { vision, voice, timer, user, system }

enum CompanionEventSeverity { info, attention, warning }

enum CompanionEventPhase { point, started, ended }

enum CompanionEventOutcome {
  observed,
  applied,
  rejected,
  shown,
  accepted,
  dismissed,
  expired,
}

extension CompanionEventSourceStorage on CompanionEventSource {
  String get storageValue => name;
}

extension CompanionEventSeverityStorage on CompanionEventSeverity {
  String get storageValue => name;
}

extension CompanionEventPhaseStorage on CompanionEventPhase {
  String get storageValue => name;
}

extension CompanionEventOutcomeStorage on CompanionEventOutcome {
  String get storageValue => name;
}

class CompanionEvent {
  const CompanionEvent({
    required this.clientEventId,
    required this.sessionId,
    required this.source,
    required this.eventType,
    required this.occurredAt,
    this.roundId,
    this.relatedEventId,
    this.severity = CompanionEventSeverity.info,
    this.phase = CompanionEventPhase.point,
    this.durationMs,
    this.confidenceScore,
    this.actionTriggered,
    this.outcome = CompanionEventOutcome.observed,
    this.signals = const <String, dynamic>{},
    this.schemaVersion = 1,
  });

  final String clientEventId;
  final String sessionId;
  final String? roundId;
  final String? relatedEventId;
  final CompanionEventSource source;
  final String eventType;
  final DateTime occurredAt;
  final CompanionEventSeverity severity;
  final CompanionEventPhase phase;
  final int? durationMs;
  final double? confidenceScore;
  final String? actionTriggered;
  final CompanionEventOutcome outcome;
  final Map<String, dynamic> signals;
  final int schemaVersion;

  factory CompanionEvent.create({
    required String sessionId,
    required CompanionEventSource source,
    required String eventType,
    String? clientEventId,
    String? roundId,
    String? relatedEventId,
    DateTime? occurredAt,
    CompanionEventSeverity severity = CompanionEventSeverity.info,
    CompanionEventPhase phase = CompanionEventPhase.point,
    Duration? duration,
    double? confidenceScore,
    String? actionTriggered,
    CompanionEventOutcome outcome = CompanionEventOutcome.observed,
    Map<String, dynamic> signals = const <String, dynamic>{},
    int schemaVersion = 1,
  }) {
    return CompanionEvent(
      clientEventId: clientEventId ?? generateClientUuid(),
      sessionId: sessionId,
      roundId: roundId,
      relatedEventId: relatedEventId,
      source: source,
      eventType: eventType,
      occurredAt: occurredAt ?? DateTime.now(),
      severity: severity,
      phase: phase,
      durationMs: duration?.inMilliseconds,
      confidenceScore: confidenceScore,
      actionTriggered: actionTriggered,
      outcome: outcome,
      signals: Map<String, dynamic>.unmodifiable(signals),
      schemaVersion: schemaVersion,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'clientEventId': clientEventId,
      'sessionId': sessionId,
      if (roundId != null) 'roundId': roundId,
      if (relatedEventId != null) 'relatedEventId': relatedEventId,
      'source': source.storageValue,
      'eventType': eventType,
      'ts': occurredAt.toUtc().toIso8601String(),
      'severity': severity.storageValue,
      'phase': phase.storageValue,
      if (durationMs != null) 'durationMs': durationMs,
      if (confidenceScore != null) 'confidenceScore': confidenceScore,
      if (actionTriggered != null) 'actionTriggered': actionTriggered,
      'outcome': outcome.storageValue,
      'signals': signals,
      'schemaVersion': schemaVersion,
    };
  }

  static Map<String, dynamic> batchPayload(Iterable<CompanionEvent> events) {
    return <String, dynamic>{
      'events': events.map((event) => event.toJson()).toList(growable: false),
    };
  }
}

String generateClientUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0'));
  final value = hex.join();
  return '${value.substring(0, 8)}-'
      '${value.substring(8, 12)}-'
      '${value.substring(12, 16)}-'
      '${value.substring(16, 20)}-'
      '${value.substring(20)}';
}
