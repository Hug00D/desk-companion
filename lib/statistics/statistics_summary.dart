class StatisticsSummary {
  const StatisticsSummary({
    required this.today,
    required this.weeklyTrend,
    required this.stateDistribution,
    required this.recentEvents,
  });

  final TodayStatistics today;
  final List<WeeklyFocusPoint> weeklyTrend;
  final StateDistribution stateDistribution;
  final List<RecentStatisticsEvent> recentEvents;

  factory StatisticsSummary.fromJson(Map<String, dynamic> json) {
    return StatisticsSummary(
      today: TodayStatistics.fromJson(_map(json['today'])),
      weeklyTrend: _listOfMaps(
        json['weeklyTrend'],
      ).map(WeeklyFocusPoint.fromJson).toList(growable: false),
      stateDistribution: StateDistribution.fromJson(
        _map(json['stateDistribution']),
      ),
      recentEvents: _listOfMaps(
        json['recentEvents'],
      ).map(RecentStatisticsEvent.fromJson).toList(growable: false),
    );
  }
}

class TodayStatistics {
  const TodayStatistics({
    this.focusSeconds = 0,
    this.completedRoundCount = 0,
    this.reminderShownCount = 0,
    this.awaySeconds = 0,
  });

  final int focusSeconds;
  final int completedRoundCount;
  final int reminderShownCount;
  final int awaySeconds;

  factory TodayStatistics.fromJson(Map<String, dynamic> json) {
    return TodayStatistics(
      focusSeconds: _int(json['focusSeconds']),
      completedRoundCount: _int(json['completedRoundCount']),
      reminderShownCount: _int(json['reminderShownCount']),
      awaySeconds: _int(json['awaySeconds']),
    );
  }
}

class WeeklyFocusPoint {
  const WeeklyFocusPoint({
    required this.date,
    this.focusSeconds = 0,
    this.focusScore,
  });

  final DateTime date;
  final int focusSeconds;
  final double? focusScore;

  factory WeeklyFocusPoint.fromJson(Map<String, dynamic> json) {
    return WeeklyFocusPoint(
      date: DateTime.tryParse(json['date']?.toString() ?? '') ?? DateTime(1970),
      focusSeconds: _int(json['focusSeconds']),
      focusScore: (json['focusScore'] as num?)?.toDouble(),
    );
  }
}

class StateDistribution {
  const StateDistribution({
    this.focusSeconds = 0,
    this.attentionSeconds = 0,
    this.fatigueSeconds = 0,
    this.awaySeconds = 0,
  });

  final int focusSeconds;
  final int attentionSeconds;
  final int fatigueSeconds;
  final int awaySeconds;

  int get totalSeconds =>
      focusSeconds + attentionSeconds + fatigueSeconds + awaySeconds;

  double ratioFor(int seconds) {
    if (totalSeconds == 0) return 0;
    return seconds / totalSeconds;
  }

  factory StateDistribution.fromJson(Map<String, dynamic> json) {
    return StateDistribution(
      focusSeconds: _int(json['focusSeconds']),
      attentionSeconds: _int(json['attentionSeconds']),
      fatigueSeconds: _int(json['fatigueSeconds']),
      awaySeconds: _int(json['awaySeconds']),
    );
  }
}

class RecentStatisticsEvent {
  const RecentStatisticsEvent({
    required this.eventType,
    required this.occurredAt,
    this.title,
    this.detail,
    this.severity,
    this.outcome,
  });

  final String eventType;
  final DateTime occurredAt;
  final String? title;
  final String? detail;
  final String? severity;
  final String? outcome;

  factory RecentStatisticsEvent.fromJson(Map<String, dynamic> json) {
    return RecentStatisticsEvent(
      eventType: json['eventType']?.toString() ?? 'unknown',
      occurredAt:
          DateTime.tryParse(json['ts']?.toString() ?? '') ?? DateTime(1970),
      title: json['title']?.toString(),
      detail: json['detail']?.toString(),
      severity: json['severity']?.toString(),
      outcome: json['outcome']?.toString(),
    );
  }
}

Map<String, dynamic> _map(dynamic value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> _listOfMaps(dynamic value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList(growable: false);
}

int _int(dynamic value) => value is num ? value.toInt() : 0;
