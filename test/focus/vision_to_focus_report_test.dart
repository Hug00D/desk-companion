import 'package:desk_companion/companion/companion_controller.dart';
import 'package:desk_companion/focus/focus_session_monitor.dart';
import 'package:desk_companion/vision/companion_state_evaluator.dart';
import 'package:desk_companion/vision/vision_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime(2026, 11, 8, 21);

  for (final personPresent in <bool?>[null, false, true]) {
    test('away reaches the report with person-mask result $personPresent', () {
      final controller = CompanionController(enableDualTrackPilot: true);
      final monitor = FocusSessionMonitor.detached()
        ..setSevereAutoPauseEnabled(false)
        ..beginSession(now: start);
      addTearDown(monitor.dispose);
      CompanionAnalysis? latest;
      for (var ms = 0; ms <= 60000; ms += 600) {
        final visible = ms < 15000;
        final frame = VisionResult.fromNativeMap({
          'hasFace': visible,
          // A face-only camera view supplies no reliable shoulder history.
          'hasPose': false,
          'poseSequence': ms ~/ 1200,
          'headPitch': 0.0,
          'headYaw': 0.0,
          'headOffsetScore': 0.0,
          'leftEye': 0.9,
          'rightEye': 0.9,
          if (!visible && personPresent != null) ...{
            'personPresenceSampled': true,
            'personPresent': personPresent,
          },
        });
        final now = start.add(Duration(milliseconds: ms));
        latest = controller.analyze(frame, observedAt: now);
        monitor.update(
          status: latest.status,
          cause: latest.cause,
          hasObservation:
              latest.status == CompanionStatus.userMissing ||
              frame.hasFace ||
              frame.hasPose,
          sessionActive: true,
          sessionRunning: true,
          sessionAutoPaused: false,
          now: now,
        );
      }
      final report = monitor.completeSession(
        plannedDuration: const Duration(minutes: 1),
        now: start.add(const Duration(minutes: 1)),
      );
      if (personPresent == true) {
        // A positive person mask cannot prove departure; keep this interval
        // unobserved instead of turning missing landmarks into focus or away.
        expect(latest!.status, isNot(CompanionStatus.userMissing));
        expect(report.awayEventCount, 0);
        expect(report.awayDuration, Duration.zero);
        expect(
          report.unobservedDuration,
          greaterThan(const Duration(seconds: 40)),
        );
      } else {
        expect(latest!.status, CompanionStatus.userMissing);
        expect(report.awayEventCount, 1);
        expect(report.awayDuration, greaterThan(const Duration(seconds: 30)));
      }
      expect(report.distractedDuration, report.awayDuration);
      expect(report.score, lessThan(30));
    });
  }
}
