import 'package:flutter_test/flutter_test.dart';

import 'package:desk_companion/focus/focus_session_monitor.dart';
import 'package:desk_companion/focus/focus_session_report.dart';
import 'package:desk_companion/vision/companion_state_evaluator.dart';

void main() {
  group('FocusSessionReport', () {
    test('builds score and grade from focus ratio and events', () {
      final report = FocusSessionReport(
        completedAt: DateTime(2026, 7, 26),
        plannedDuration: const Duration(minutes: 25),
        effectiveFocusDuration: const Duration(minutes: 16),
        distractedDuration: const Duration(minutes: 4),
        eventCounts: const <CompanionStatus, int>{
          CompanionStatus.distracted: 2,
          CompanionStatus.sleeping: 1,
        },
        causeEventCounts: const <CompanionCause, int>{
          CompanionCause.headTurned: 2,
          CompanionCause.postureDown: 1,
        },
      );

      expect(report.hasEnoughData, isTrue);
      expect(report.focusRatio, closeTo(0.8, 0.001));
      expect(report.attentionEventCount, 2);
      expect(report.fatigueEventCount, 1);
      expect(report.causeEventCountFor(CompanionCause.postureDown), 1);
      expect(report.score, 82);
      expect(report.grade, 'A');
    });

    test('does not force a score when observation coverage is too low', () {
      final report = FocusSessionReport(
        completedAt: DateTime(2026, 7, 26),
        plannedDuration: const Duration(minutes: 25),
        effectiveFocusDuration: const Duration(seconds: 5),
        distractedDuration: Duration.zero,
        eventCounts: const <CompanionStatus, int>{},
      );

      expect(report.hasEnoughData, isFalse);
      expect(report.score, isNull);
      expect(report.grade, '--');
    });
  });

  test('FocusSessionMonitor keeps a snapshot after completion', () {
    final monitor = FocusSessionMonitor.detached();
    final startedAt = DateTime(2026, 7, 26, 9);
    monitor.beginSession(now: startedAt);

    for (var seconds = 0; seconds <= 6; seconds += 2) {
      monitor.update(
        status: CompanionStatus.distracted,
        cause: CompanionCause.headTurned,
        sessionActive: true,
        sessionRunning: true,
        sessionAutoPaused: false,
        now: startedAt.add(Duration(seconds: seconds)),
      );
    }

    final report = monitor.completeSession(
      plannedDuration: const Duration(minutes: 25),
      now: startedAt.add(const Duration(minutes: 25)),
    );

    expect(report.distractedDuration, const Duration(seconds: 6));
    expect(report.eventCountFor(CompanionStatus.distracted), 1);
    expect(monitor.lastCompletedReport, same(report));
    expect(monitor.activeEpisodeStatus, isNull);
  });
}
