import '../events/companion_event.dart';

enum FocusRoundType { focus, breakTime }

enum FocusRoundStatus { active, paused, completed, stopped }

enum FocusRoundEndReason { completed, userStopped, sessionEnded, error }

class FocusRoundSnapshot {
  const FocusRoundSnapshot({
    required this.clientRoundId,
    required this.sessionId,
    required this.roundNumber,
    required this.type,
    required this.status,
    required this.targetSeconds,
    required this.startedAt,
    this.serverRoundId,
    this.actualSeconds = 0,
    this.pausedSeconds = 0,
    this.endedAt,
    this.endReason,
    this.schemaVersion = 1,
  });

  final String clientRoundId;
  final String? serverRoundId;
  final String sessionId;
  final int roundNumber;
  final FocusRoundType type;
  final FocusRoundStatus status;
  final int targetSeconds;
  final int actualSeconds;
  final int pausedSeconds;
  final DateTime startedAt;
  final DateTime? endedAt;
  final FocusRoundEndReason? endReason;
  final int schemaVersion;

  factory FocusRoundSnapshot.start({
    required String sessionId,
    required int roundNumber,
    required FocusRoundType type,
    required int targetSeconds,
    DateTime? startedAt,
  }) {
    return FocusRoundSnapshot(
      clientRoundId: generateClientUuid(),
      sessionId: sessionId,
      roundNumber: roundNumber,
      type: type,
      status: FocusRoundStatus.active,
      targetSeconds: targetSeconds,
      startedAt: startedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'clientRoundId': clientRoundId,
      if (serverRoundId != null) 'roundId': serverRoundId,
      'sessionId': sessionId,
      'roundNumber': roundNumber,
      'roundType': type == FocusRoundType.breakTime ? 'break' : 'focus',
      'status': status.name,
      'targetSeconds': targetSeconds,
      'actualSeconds': actualSeconds,
      'pausedSeconds': pausedSeconds,
      'startAt': startedAt.toUtc().toIso8601String(),
      if (endedAt != null) 'endAt': endedAt!.toUtc().toIso8601String(),
      if (endReason != null) 'endReason': endReason!.name,
      'schemaVersion': schemaVersion,
    };
  }
}
