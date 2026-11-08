import 'dart:math' as math;

import '../vision/companion_state_evaluator.dart';

class FocusSessionReport {
  FocusSessionReport({
    required this.completedAt,
    required this.plannedDuration,
    required this.effectiveFocusDuration,
    required this.distractedDuration,
    this.awayDuration,
    required Map<CompanionStatus, int> eventCounts,
    Map<CompanionCause, int> causeEventCounts = const <CompanionCause, int>{},
    this.recordedEvaluation,
  }) : eventCounts = Map<CompanionStatus, int>.unmodifiable(eventCounts),
       causeEventCounts = Map<CompanionCause, int>.unmodifiable(
         causeEventCounts,
       );

  final DateTime completedAt;
  final Duration plannedDuration;
  final Duration effectiveFocusDuration;
  final Duration distractedDuration;
  // A subset of distractedDuration; null for reports saved before v2.
  final Duration? awayDuration;
  final Map<CompanionStatus, int> eventCounts;
  final Map<CompanionCause, int> causeEventCounts;
  final FocusReportEvaluation? recordedEvaluation;
  static const currentScoringVersion = 2;
  int get scoringVersion =>
      recordedEvaluation?.version ?? currentScoringVersion;
  bool get usesLegacyScoring => scoringVersion < currentScoringVersion;

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'completedAt': completedAt.toUtc().toIso8601String(),
    'plannedMilliseconds': plannedDuration.inMilliseconds,
    'effectiveFocusMilliseconds': effectiveFocusDuration.inMilliseconds,
    'distractedMilliseconds': distractedDuration.inMilliseconds,
    if (awayDuration != null) 'awayMilliseconds': awayDuration!.inMilliseconds,
    'eventCounts': {
      for (final entry in eventCounts.entries) entry.key.name: entry.value,
    },
    'causeEventCounts': {
      for (final entry in causeEventCounts.entries) entry.key.name: entry.value,
    },
    'evaluation': {
      'version': scoringVersion,
      'score': score,
      'grade': grade,
      'feedback': feedback,
    },
  };

  factory FocusSessionReport.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported report version');
    }
    final evaluation = json['evaluation'];
    if (evaluation is! Map ||
        (evaluation['version'] != 1 &&
            evaluation['version'] != currentScoringVersion) ||
        (evaluation['score'] != null &&
            (evaluation['score'] is! int ||
                evaluation['score'] < 0 ||
                evaluation['score'] > 100)) ||
        evaluation['grade'] is! String ||
        evaluation['feedback'] is! String) {
      throw const FormatException('Invalid saved report evaluation');
    }
    int milliseconds(String key) {
      final value = json[key];
      if (value is! int || value < 0) throw FormatException('Invalid $key');
      return value;
    }

    Map<T, int> counts<T extends Enum>(String key, List<T> values) {
      final data = json[key];
      if (data is! Map) throw FormatException('Invalid $key');
      final result = <T, int>{};
      for (final value in values) {
        final count = data[value.name];
        if (count == null) continue;
        if (count is! int || count < 0) {
          throw FormatException('Invalid $key count');
        }
        result[value] = count;
      }
      return result;
    }

    return FocusSessionReport(
      completedAt: DateTime.parse(json['completedAt'] as String).toLocal(),
      plannedDuration: Duration(
        milliseconds: milliseconds('plannedMilliseconds'),
      ),
      effectiveFocusDuration: Duration(
        milliseconds: milliseconds('effectiveFocusMilliseconds'),
      ),
      distractedDuration: Duration(
        milliseconds: milliseconds('distractedMilliseconds'),
      ),
      awayDuration: json.containsKey('awayMilliseconds')
          ? Duration(milliseconds: milliseconds('awayMilliseconds'))
          : null,
      eventCounts: counts('eventCounts', CompanionStatus.values),
      causeEventCounts: counts('causeEventCounts', CompanionCause.values),
      recordedEvaluation: FocusReportEvaluation(
        version: evaluation['version'] as int,
        score: evaluation['score'] as int?,
        grade: evaluation['grade'] as String,
        feedback: evaluation['feedback'] as String,
      ),
    );
  }

  Duration get observedDuration => effectiveFocusDuration + distractedDuration;

  Duration get unobservedDuration => plannedDuration > observedDuration
      ? plannedDuration - observedDuration
      : Duration.zero;

  double get sessionFocusRatio {
    final planned = plannedDuration.inMilliseconds;
    if (planned <= 0) return 0;
    return (effectiveFocusDuration.inMilliseconds / planned).clamp(0, 1);
  }

  int eventCountFor(CompanionStatus status) => eventCounts[status] ?? 0;

  int causeEventCountFor(CompanionCause cause) => causeEventCounts[cause] ?? 0;

  int get totalEventCount =>
      eventCounts.values.fold<int>(0, (total, count) => total + count);

  int get attentionEventCount =>
      eventCountFor(CompanionStatus.attention) +
      eventCountFor(CompanionStatus.distracted);

  int get fatigueEventCount =>
      eventCountFor(CompanionStatus.fatigue) +
      eventCountFor(CompanionStatus.sleeping);

  int get awayEventCount => eventCountFor(CompanionStatus.userMissing);

  double get focusRatio {
    final observed = observedDuration.inMilliseconds;
    if (observed <= 0) return 0;
    return (effectiveFocusDuration.inMilliseconds / observed).clamp(0, 1);
  }

  double get coverageRatio {
    final planned = plannedDuration.inMilliseconds;
    if (planned <= 0) return 0;
    return (observedDuration.inMilliseconds / planned).clamp(0, 1);
  }

  bool get hasEnoughData {
    final plannedSeconds = plannedDuration.inSeconds;
    if (plannedSeconds <= 0) return false;
    final requiredSeconds = math.min(
      30,
      math.max(10, (plannedSeconds * 0.2).ceil()),
    );
    return observedDuration.inSeconds >= requiredSeconds;
  }

  int? get score {
    if (recordedEvaluation != null) return recordedEvaluation!.score;
    if (!hasEnoughData) return null;

    // Missing observations must never improve the score by shrinking its base.
    final focusPoints = sessionFocusRatio * 100;
    final severeEvents = fatigueEventCount + awayEventCount;
    final eventPenalty = math.min(10, attentionEventCount + (severeEvents * 2));
    return (focusPoints - eventPenalty).round().clamp(0, 100);
  }

  String get grade {
    if (recordedEvaluation != null) return recordedEvaluation!.grade;
    final currentScore = score;
    if (currentScore == null) return '--';
    if (currentScore >= 90) return 'S';
    if (currentScore >= 80) return 'A';
    if (currentScore >= 70) return 'B';
    if (currentScore >= 60) return 'C';
    return 'D';
  }

  String get feedback {
    if (recordedEvaluation != null) return recordedEvaluation!.feedback;
    final currentScore = score;
    if (currentScore == null) {
      return '這輪已完成，但有效觀測資料不足，先不勉強評分。';
    }
    if (coverageRatio < 0.8) {
      return '這輪有部分時間未取得有效觀測，未觀測時間未計入專注；可以確認相機狀態後再試。';
    }
    if (currentScore >= 90) {
      return '節奏很穩，這輪幾乎都守在專注狀態。';
    }
    if (currentScore >= 80) {
      return '表現很好，幾次小波動也有順利拉回來。';
    }
    if (currentScore >= 70) {
      return '完整撐完這一輪了，下輪再把分心時間縮短一些。';
    }
    if (currentScore >= 60) {
      return '這輪有些起伏，先休息一下再開始會更有效率。';
    }
    return '今天可能有點累，休息、補水，再決定要不要開下一輪。';
  }
}

class FocusReportEvaluation {
  const FocusReportEvaluation({
    this.version = 1,
    required this.score,
    required this.grade,
    required this.feedback,
  });

  final int? score;
  final int version;
  final String grade;
  final String feedback;
}
