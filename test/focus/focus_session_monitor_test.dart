import 'package:desk_companion/focus/focus_session_monitor.dart';
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

    test('posture down auto-pauses and only waits for recovery afterward', () {
      final monitor = FocusSessionMonitor.detached();
      final start = DateTime(2026, 7, 6, 10);
      monitor.beginSession(now: start);

      expect(_step(monitor, CompanionStatus.postureDown, start, 0), isEmpty);
      expect(_types(_step(monitor, CompanionStatus.postureDown, start, 1)), [
        FocusInterventionType.reminder,
      ]);
      for (var second = 2; second < 8; second += 1) {
        _step(monitor, CompanionStatus.postureDown, start, second);
      }
      expect(_types(_step(monitor, CompanionStatus.postureDown, start, 8)), [
        FocusInterventionType.autoPause,
      ]);

      expect(
        _step(
          monitor,
          CompanionStatus.drowsy,
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
          CompanionStatus.drowsy,
          start,
          20,
          sessionRunning: false,
          sessionAutoPaused: true,
        ),
        isEmpty,
      );
      expect(monitor.eventCountFor(CompanionStatus.drowsy), 0);

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
  });
}

List<FocusIntervention> _step(
  FocusSessionMonitor monitor,
  CompanionStatus status,
  DateTime start,
  int seconds, {
  bool sessionActive = true,
  bool sessionRunning = true,
  bool sessionAutoPaused = false,
}) {
  return monitor.update(
    status: status,
    sessionActive: sessionActive,
    sessionRunning: sessionRunning,
    sessionAutoPaused: sessionAutoPaused,
    now: start.add(Duration(seconds: seconds)),
  );
}

List<FocusInterventionType> _types(List<FocusIntervention> interventions) {
  return interventions.map((item) => item.type).toList();
}
