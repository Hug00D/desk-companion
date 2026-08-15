import 'dart:math' as math;

import '../vision/companion_state_evaluator.dart';

class FocusSessionReport {
  FocusSessionReport({
    required this.completedAt,
    required this.plannedDuration,
    required this.effectiveFocusDuration,
    required this.distractedDuration,
    required Map<CompanionStatus, int> eventCounts,
    Map<CompanionCause, int> causeEventCounts = const <CompanionCause, int>{},
  }) : eventCounts = Map<CompanionStatus, int>.unmodifiable(eventCounts),
       causeEventCounts = Map<CompanionCause, int>.unmodifiable(
         causeEventCounts,
       );

  final DateTime completedAt;
  final Duration plannedDuration;
  final Duration effectiveFocusDuration;
  final Duration distractedDuration;
  final Map<CompanionStatus, int> eventCounts;
  final Map<CompanionCause, int> causeEventCounts;

  Duration get observedDuration => effectiveFocusDuration + distractedDuration;

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
    final observedSeconds = observedDuration.inSeconds;
    if (observedSeconds <= 0) return 0;
    return (effectiveFocusDuration.inSeconds / observedSeconds).clamp(0, 1);
  }

  double get coverageRatio {
    final plannedSeconds = plannedDuration.inSeconds;
    if (plannedSeconds <= 0) return 0;
    return (observedDuration.inSeconds / plannedSeconds).clamp(0, 1);
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
    if (!hasEnoughData) return null;

    const completionPoints = 20.0;
    final focusPoints = focusRatio * 70;
    final severeEvents = fatigueEventCount + awayEventCount;
    final eventPenalty = math.min(10, attentionEventCount + (severeEvents * 2));
    return (completionPoints + focusPoints + 10 - eventPenalty).round().clamp(
      0,
      100,
    );
  }

  String get grade {
    final currentScore = score;
    if (currentScore == null) return '--';
    if (currentScore >= 90) return 'S';
    if (currentScore >= 80) return 'A';
    if (currentScore >= 70) return 'B';
    if (currentScore >= 60) return 'C';
    return 'D';
  }

  String get feedback {
    final currentScore = score;
    if (currentScore == null) {
      return '這輪已完成，但有效觀測資料不足，先不勉強評分。';
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
