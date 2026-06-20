import '../events/companion_event.dart';

enum StudySessionStatus { active, completed, stopped, abandoned }

enum StudySessionEndReason { completed, userStopped, appClosed, error, unknown }

class StudySessionSnapshot {
  const StudySessionSnapshot({
    required this.clientSessionId,
    required this.startedAt,
    required this.status,
    required this.timezone,
    this.serverSessionId,
    this.endedAt,
    this.endReason,
    this.mode = 'focus_monitoring',
    this.targetSeconds,
    this.monitoredSeconds = 0,
    this.focusSeconds = 0,
    this.attentionSeconds = 0,
    this.distractedSeconds = 0,
    this.fatigueSeconds = 0,
    this.drowsySeconds = 0,
    this.postureDownSeconds = 0,
    this.awaySeconds = 0,
    this.pausedSeconds = 0,
    this.breakSeconds = 0,
    this.reminderShownCount = 0,
    this.summary = const <String, dynamic>{},
    this.config = const <String, dynamic>{},
    this.revision = 0,
    this.schemaVersion = 1,
  });

  final String clientSessionId;
  final String? serverSessionId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final StudySessionStatus status;
  final StudySessionEndReason? endReason;
  final String mode;
  final String timezone;
  final int? targetSeconds;
  final int monitoredSeconds;
  final int focusSeconds;
  final int attentionSeconds;
  final int distractedSeconds;
  final int fatigueSeconds;
  final int drowsySeconds;
  final int postureDownSeconds;
  final int awaySeconds;
  final int pausedSeconds;
  final int breakSeconds;
  final int reminderShownCount;
  final Map<String, dynamic> summary;
  final Map<String, dynamic> config;
  final int revision;
  final int schemaVersion;

  factory StudySessionSnapshot.start({
    required String timezone,
    String mode = 'focus_monitoring',
    int? targetSeconds,
    Map<String, dynamic> config = const <String, dynamic>{},
    DateTime? startedAt,
  }) {
    return StudySessionSnapshot(
      clientSessionId: generateClientUuid(),
      startedAt: startedAt ?? DateTime.now(),
      status: StudySessionStatus.active,
      timezone: timezone,
      mode: mode,
      targetSeconds: targetSeconds,
      config: Map<String, dynamic>.unmodifiable(config),
    );
  }

  Map<String, dynamic> toCreatePayload() {
    return <String, dynamic>{
      'clientSessionId': clientSessionId,
      'startAt': startedAt.toUtc().toIso8601String(),
      'status': status.name,
      'mode': mode,
      'timezone': timezone,
      if (targetSeconds != null) 'targetSeconds': targetSeconds,
      'config': config,
      'schemaVersion': schemaVersion,
    };
  }

  Map<String, dynamic> toUpdatePayload() {
    return <String, dynamic>{
      'clientSessionId': clientSessionId,
      if (serverSessionId != null) 'sessionId': serverSessionId,
      'startAt': startedAt.toUtc().toIso8601String(),
      if (endedAt != null) 'endAt': endedAt!.toUtc().toIso8601String(),
      'status': status.name,
      if (endReason != null) 'endReason': endReason!.name,
      'mode': mode,
      'timezone': timezone,
      if (targetSeconds != null) 'targetSeconds': targetSeconds,
      'monitoredSeconds': monitoredSeconds,
      'focusSeconds': focusSeconds,
      'attentionSeconds': attentionSeconds,
      'distractedSeconds': distractedSeconds,
      'fatigueSeconds': fatigueSeconds,
      'drowsySeconds': drowsySeconds,
      'postureDownSeconds': postureDownSeconds,
      'awaySeconds': awaySeconds,
      'pausedSeconds': pausedSeconds,
      'breakSeconds': breakSeconds,
      'reminderCount': reminderShownCount,
      'summary': summary,
      'config': config,
      'revision': revision,
      'schemaVersion': schemaVersion,
    };
  }
}
