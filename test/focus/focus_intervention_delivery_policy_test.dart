import 'package:desk_companion/focus/focus_intervention_delivery_policy.dart';
import 'package:desk_companion/focus/focus_session_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = FocusInterventionDeliveryPolicy();

  test('quiet mode preserves recording and configured auto-pause', () {
    expect(
      policy.shouldDeliver(
        FocusInterventionType.eventRecorded,
        quietMode: true,
      ),
      isTrue,
    );
    expect(
      policy.shouldDeliver(FocusInterventionType.autoPause, quietMode: true),
      isTrue,
    );
  });

  test('quiet mode suppresses proactive reminders and questions', () {
    for (final type in <FocusInterventionType>[
      FocusInterventionType.reminder,
      FocusInterventionType.checkIn,
      FocusInterventionType.offerPause,
      FocusInterventionType.recovered,
    ]) {
      expect(
        policy.shouldDeliver(type, quietMode: true),
        isFalse,
        reason: type.name,
      );
    }
  });

  test('all focus effects remain available when quiet mode is off', () {
    for (final type in FocusInterventionType.values) {
      expect(
        policy.shouldDeliver(type, quietMode: false),
        isTrue,
        reason: type.name,
      );
    }
  });
}
