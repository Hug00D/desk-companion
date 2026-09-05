import 'package:desk_companion/focus/focus_session_monitor.dart';
import 'package:desk_companion/focus/reminder_policy.dart';
import 'package:desk_companion/vision/companion_state_evaluator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FocusSessionMonitor hybrid evidence', () {
    test('long distraction reminds, records once, then offers pause', () {
      final monitor = FocusSessionMonitor.detached();
      final start = DateTime(2026, 7, 6, 10);
      monitor.beginSession(now: start);

      expect(_step(monitor, CompanionStatus.distracted, start, 0), isEmpty);
      expect(_types(_step(monitor, CompanionStatus.distracted, start, 3)), [
        FocusInterventionType.reminder,
      ]);
      expect(_types(_step(monitor, CompanionStatus.distracted, start, 5)), [
        FocusInterventionType.eventRecorded,
      ]);

      for (var second = 6; second < 15; second += 1) {
        expect(
          _step(monitor, CompanionStatus.distracted, start, second),
          isEmpty,
        );
      }
      expect(_types(_step(monitor, CompanionStatus.distracted, start, 15)), [
        FocusInterventionType.offerPause,
      ]);
      expect(_step(monitor, CompanionStatus.distracted, start, 16), isEmpty);
      expect(monitor.eventCountFor(CompanionStatus.distracted), 1);
    });

    test(
      'brief normal and another status do not erase distraction evidence',
      () {
        final monitor = FocusSessionMonitor.detached();
        final start = DateTime(2026, 7, 6, 10);
        monitor.beginSession(now: start);

        _step(monitor, CompanionStatus.distracted, start, 0);
        _step(monitor, CompanionStatus.distracted, start, 1);
        _step(monitor, CompanionStatus.normal, start, 2);
        _step(monitor, CompanionStatus.attention, start, 3);
        _step(monitor, CompanionStatus.distracted, start, 4);

        expect(_types(_step(monitor, CompanionStatus.distracted, start, 5)), [
          FocusInterventionType.reminder,
        ]);
        expect(monitor.activeEpisodeStatus, CompanionStatus.distracted);
      },
    );

    test('three seconds without a status starts a fresh episode', () {
      final monitor = FocusSessionMonitor.detached();
      final start = DateTime(2026, 7, 6, 10);
      monitor.beginSession(now: start);

      _step(monitor, CompanionStatus.distracted, start, 0);
      _step(monitor, CompanionStatus.distracted, start, 1);
      _step(monitor, CompanionStatus.normal, start, 2);
      _step(monitor, CompanionStatus.normal, start, 3);
      _step(monitor, CompanionStatus.normal, start, 4);
      _step(monitor, CompanionStatus.normal, start, 5);

      expect(monitor.activeEpisodeStatus, isNull);
      expect(_step(monitor, CompanionStatus.distracted, start, 6), isEmpty);
      expect(_step(monitor, CompanionStatus.distracted, start, 7), isEmpty);
    });

    test('general mode uses evidence reminders without session actions', () {
      final monitor = FocusSessionMonitor.detached();
      final start = DateTime(2026, 7, 6, 10);

      for (var second = 0; second < 3; second += 1) {
        expect(
          _step(
            monitor,
            CompanionStatus.distracted,
            start,
            second,
            sessionActive: false,
            sessionRunning: false,
          ),
          isEmpty,
        );
      }
      expect(
        _types(
          _step(
            monitor,
            CompanionStatus.distracted,
            start,
            3,
            sessionActive: false,
            sessionRunning: false,
          ),
        ),
        [FocusInterventionType.reminder],
      );
      for (var second = 4; second <= 16; second += 1) {
        expect(
          _step(
            monitor,
            CompanionStatus.distracted,
            start,
            second,
            sessionActive: false,
            sessionRunning: false,
          ),
          isEmpty,
        );
      }
      expect(monitor.totalEventCount, 0);
    });

    test('sleeping auto-pauses and only waits for recovery afterward', () {
      final monitor = FocusSessionMonitor.detached();
      final start = DateTime(2026, 7, 6, 10);
      monitor.beginSession(now: start);

      expect(_step(monitor, CompanionStatus.sleeping, start, 0), isEmpty);
      expect(_step(monitor, CompanionStatus.sleeping, start, 1), isEmpty);
      expect(_types(_step(monitor, CompanionStatus.sleeping, start, 2)), [
        FocusInterventionType.reminder,
      ]);
      for (var second = 3; second < 8; second += 1) {
        _step(monitor, CompanionStatus.sleeping, start, second);
      }
      expect(_types(_step(monitor, CompanionStatus.sleeping, start, 8)), [
        FocusInterventionType.autoPause,
      ]);

      expect(
        _step(
          monitor,
          CompanionStatus.sleeping,
          start,
          9,
          sessionRunning: false,
          sessionAutoPaused: true,
        ),
        isEmpty,
      );
      expect(
        _step(
          monitor,
          CompanionStatus.sleeping,
          start,
          20,
          sessionRunning: false,
          sessionAutoPaused: true,
        ),
        isEmpty,
      );
      expect(monitor.eventCountFor(CompanionStatus.sleeping), 1);
      expect(monitor.causeEventCountFor(CompanionCause.drowsy), 1);

      expect(
        _step(
          monitor,
          CompanionStatus.normal,
          start,
          21,
          sessionRunning: false,
          sessionAutoPaused: true,
        ),
        isEmpty,
      );
      expect(
        _types(
          _step(
            monitor,
            CompanionStatus.normal,
            start,
            24,
            sessionRunning: false,
            sessionAutoPaused: true,
          ),
        ),
        [FocusInterventionType.recovered],
      );
      expect(
        _step(
          monitor,
          CompanionStatus.normal,
          start,
          30,
          sessionRunning: false,
          sessionAutoPaused: true,
        ),
        isEmpty,
      );
    });

    test('long distraction can be configured to auto-pause', () {
      final monitor = FocusSessionMonitor.detached()
        ..setLongDistractionAutoPauseEnabled(true);
      final start = DateTime(2026, 7, 6, 10);
      monitor.beginSession(now: start);

      List<FocusIntervention> latest = const <FocusIntervention>[];
      for (var second = 0; second <= 15; second += 1) {
        latest = _step(monitor, CompanionStatus.distracted, start, second);
      }
      expect(_types(latest), [FocusInterventionType.autoPause]);
    });

    test('sleeping interventions retain posture-down cause', () {
      final monitor = FocusSessionMonitor.detached();
      final start = DateTime(2026, 7, 6, 10);
      monitor.beginSession(now: start);

      _step(
        monitor,
        CompanionStatus.sleeping,
        start,
        0,
        cause: CompanionCause.postureDown,
      );
      final reminder = _step(
        monitor,
        CompanionStatus.sleeping,
        start,
        2,
        cause: CompanionCause.postureDown,
      );
      final recorded = _step(
        monitor,
        CompanionStatus.sleeping,
        start,
        5,
        cause: CompanionCause.postureDown,
      );

      expect(reminder.single.cause, CompanionCause.postureDown);
      expect(recorded.single.cause, CompanionCause.postureDown);
      expect(monitor.causeEventCountFor(CompanionCause.postureDown), 1);
      expect(monitor.causeEventCountFor(CompanionCause.drowsy), 0);
    });

    test('tracks effective and distracted time separately', () {
      final monitor = FocusSessionMonitor.detached();
      final start = DateTime(2026, 7, 6, 10);
      monitor.beginSession(now: start);

      _step(monitor, CompanionStatus.normal, start, 1);
      _step(monitor, CompanionStatus.distracted, start, 2);
      _step(monitor, CompanionStatus.distracted, start, 3);

      expect(monitor.effectiveFocusDuration, const Duration(seconds: 2));
      expect(monitor.distractedDuration, const Duration(seconds: 1));
    });

    test('conservative policy asks once and never auto-pauses', () {
      final monitor = FocusSessionMonitor.detached()
        ..setExperimentalReminderPolicyEnabled(true);
      final start = DateTime(2026, 9, 5, 10);
      monitor.beginSession(now: start);

      final beforeThreshold = <FocusIntervention>[];
      for (var second = 0; second < 8; second += 1) {
        beforeThreshold.addAll(
          _step(
            monitor,
            CompanionStatus.sleeping,
            start,
            second,
            cause: CompanionCause.postureDown,
          ),
        );
      }
      expect(_types(beforeThreshold), [FocusInterventionType.eventRecorded]);
      final atThreshold = _step(
        monitor,
        CompanionStatus.sleeping,
        start,
        8,
        cause: CompanionCause.postureDown,
      );
      expect(_types(atThreshold), [FocusInterventionType.checkIn]);

      for (var second = 9; second <= 30; second += 1) {
        final interventions = _step(
          monitor,
          CompanionStatus.sleeping,
          start,
          second,
          cause: CompanionCause.postureDown,
        );
        expect(
          interventions.where(
            (item) =>
                item.type == FocusInterventionType.checkIn ||
                item.type == FocusInterventionType.autoPause,
          ),
          isEmpty,
        );
      }
    });

    test('conservative policy records absence without interrupting', () {
      final monitor = FocusSessionMonitor.detached()
        ..setExperimentalReminderPolicyEnabled(true);
      final start = DateTime(2026, 9, 5, 10);
      monitor.beginSession(now: start);

      final interventions = <FocusIntervention>[];
      for (var second = 0; second <= 20; second += 1) {
        interventions.addAll(
          _step(monitor, CompanionStatus.userMissing, start, second),
        );
      }

      expect(interventions.map((item) => item.type), [
        FocusInterventionType.eventRecorded,
      ]);
    });

    test(
      'conservative remind-later response re-prompts after five minutes',
      () {
        final monitor = FocusSessionMonitor.detached()
          ..setExperimentalReminderPolicyEnabled(true);
        final start = DateTime(2026, 9, 5, 10);
        monitor.beginSession(now: start);

        for (var second = 0; second < 15; second += 1) {
          _step(monitor, CompanionStatus.distracted, start, second);
        }
        expect(_types(_step(monitor, CompanionStatus.distracted, start, 15)), [
          FocusInterventionType.checkIn,
        ]);
        monitor.recordReminderResponse(
          status: CompanionStatus.distracted,
          cause: CompanionCause.headTurned,
          response: ReminderPolicyResponse.remindLater,
          now: start.add(const Duration(seconds: 15)),
        );

        expect(_step(monitor, CompanionStatus.distracted, start, 314), isEmpty);
        expect(_types(_step(monitor, CompanionStatus.distracted, start, 315)), [
          FocusInterventionType.checkIn,
        ]);
      },
    );
  });
}

List<FocusIntervention> _step(
  FocusSessionMonitor monitor,
  CompanionStatus status,
  DateTime start,
  int seconds, {
  CompanionCause? cause,
  bool sessionActive = true,
  bool sessionRunning = true,
  bool sessionAutoPaused = false,
}) {
  return monitor.update(
    status: status,
    cause: cause ?? _defaultCauseForStatus(status),
    sessionActive: sessionActive,
    sessionRunning: sessionRunning,
    sessionAutoPaused: sessionAutoPaused,
    now: start.add(Duration(seconds: seconds)),
  );
}

CompanionCause _defaultCauseForStatus(CompanionStatus status) {
  switch (status) {
    case CompanionStatus.normal:
      return CompanionCause.none;
    case CompanionStatus.attention:
    case CompanionStatus.fatigue:
      return CompanionCause.eyeClosed;
    case CompanionStatus.distracted:
      return CompanionCause.headTurned;
    case CompanionStatus.sleeping:
      return CompanionCause.drowsy;
    case CompanionStatus.userMissing:
      return CompanionCause.userAway;
  }
}

List<FocusInterventionType> _types(List<FocusIntervention> interventions) {
  return interventions.map((item) => item.type).toList();
}
