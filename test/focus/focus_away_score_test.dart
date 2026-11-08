import 'package:desk_companion/focus/focus_session_monitor.dart';
import 'package:desk_companion/focus/focus_session_report.dart';
import 'package:desk_companion/vision/companion_state_evaluator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026, 11, 8, 20);
  late FocusSessionMonitor monitor;

  void sample(
    int second,
    CompanionStatus status, {
    bool running = true,
    bool valid = true,
  }) {
    monitor.update(
      status: status,
      cause: status == CompanionStatus.userMissing
          ? CompanionCause.userAway
          : CompanionCause.none,
      sessionActive: true,
      sessionRunning: running,
      sessionAutoPaused: false,
      hasObservation: valid,
      now: start.add(Duration(seconds: second)),
    );
  }

  FocusSessionReport complete() => monitor.completeSession(
    plannedDuration: const Duration(minutes: 1),
    now: start.add(const Duration(minutes: 1)),
  );

  setUp(() {
    monitor = FocusSessionMonitor.detached();
    monitor.setSevereAutoPauseEnabled(false);
    monitor.beginSession(now: start);
  });
  tearDown(() => monitor.dispose());

  test('twenty seconds focused then forty seconds away cannot score 100', () {
    for (var second = 0; second <= 60; second++) {
      sample(
        second,
        second < 20 ? CompanionStatus.normal : CompanionStatus.userMissing,
      );
    }
    final report = complete();
    expect(report.effectiveFocusDuration, const Duration(seconds: 20));
    expect(report.distractedDuration, const Duration(seconds: 40));
    expect(report.awayDuration, const Duration(seconds: 40));
    expect(report.observedDuration, const Duration(minutes: 1));
    expect(report.unobservedDuration, Duration.zero);
    expect(report.awayEventCount, 1);
    expect(report.score, 31);
    final restored = FocusSessionReport.fromJson(report.toJson());
    expect(restored.score, 31);
    expect(restored.awayDuration, const Duration(seconds: 40));
    expect(restored.scoringVersion, 2);
  });

  test('all away has enough evidence but scores zero', () {
    for (var second = 0; second <= 60; second++) {
      sample(second, CompanionStatus.userMissing);
    }
    final report = complete();
    expect(report.hasEnoughData, isTrue);
    expect(report.awayDuration, const Duration(minutes: 1));
    expect(report.score, 0);
  });

  test(
    'a normal fragment followed by missing data does not become perfect',
    () {
      for (var second = 0; second <= 15; second++) {
        sample(second, CompanionStatus.normal);
      }
      final report = complete();
      expect(report.focusRatio, 1);
      expect(report.coverageRatio, 0.25);
      expect(report.unobservedDuration, const Duration(seconds: 45));
      expect(report.awayDuration, Duration.zero);
      expect(report.score, 25);
    },
  );

  test('no first observation and invalid normal frames never earn focus', () {
    sample(2, CompanionStatus.normal, valid: false);
    sample(3, CompanionStatus.normal, valid: false);
    expect(monitor.lastIntervalRecorded, isFalse);
    sample(4, CompanionStatus.normal);
    sample(5, CompanionStatus.normal);
    expect(monitor.lastIntervalRecorded, isTrue);
    final report = complete();
    expect(report.effectiveFocusDuration, const Duration(seconds: 1));
    expect(report.unobservedDuration, const Duration(seconds: 59));
    expect(report.score, isNull);
  });

  test(
    'a long sample gap remains unobserved rather than inferred as focus',
    () {
      sample(0, CompanionStatus.normal);
      sample(1, CompanionStatus.normal);
      sample(50, CompanionStatus.normal);
      expect(monitor.lastSampleGap, const Duration(seconds: 49));
      expect(monitor.lastIntervalRecorded, isFalse);
      sample(51, CompanionStatus.normal);
      final report = complete();
      expect(report.effectiveFocusDuration, const Duration(seconds: 2));
      expect(report.score, isNull);
    },
  );

  test('paused observations do not leak into resumed focus duration', () {
    sample(0, CompanionStatus.normal);
    sample(1, CompanionStatus.normal);
    sample(2, CompanionStatus.userMissing, running: false);
    sample(3, CompanionStatus.userMissing, running: false);
    expect(monitor.lastIntervalRecorded, isFalse);
    sample(4, CompanionStatus.normal);
    sample(5, CompanionStatus.normal);
    final report = complete();
    expect(report.effectiveFocusDuration, const Duration(seconds: 2));
    expect(report.awayDuration, Duration.zero);
  });

  test('a complete normal round still earns 100', () {
    for (var second = 0; second <= 60; second++) {
      sample(second, CompanionStatus.normal);
    }
    expect(complete().score, 100);
  });

  test('completion includes a recent final sample interval', () {
    for (var second = 0; second < 60; second++) {
      sample(second, CompanionStatus.normal);
    }
    final report = complete();
    expect(report.observedDuration, const Duration(minutes: 1));
    expect(report.score, 100);
  });
}
