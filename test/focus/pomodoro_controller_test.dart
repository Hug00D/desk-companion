import 'package:flutter_test/flutter_test.dart';

import 'package:desk_companion/focus/pomodoro_controller.dart';

void main() {
  final controller = PomodoroController();

  setUp(controller.stop);
  tearDown(controller.stop);

  test('navigation pause is visible and can be resumed', () {
    controller.start(durationMinutes: 1);

    controller.pause(reason: PomodoroPauseReason.navigation);

    expect(controller.status, PomodoroStatus.paused);
    expect(controller.pauseReason, PomodoroPauseReason.navigation);
    expect(controller.isAutoPaused, isTrue);

    controller.resume();

    expect(controller.status, PomodoroStatus.running);
    expect(controller.pauseReason, isNull);
  });

  test('manual pause remains distinguishable from navigation pause', () {
    controller.start(durationMinutes: 1);

    controller.pause();

    expect(controller.status, PomodoroStatus.paused);
    expect(controller.pauseReason, PomodoroPauseReason.manual);
    expect(controller.isAutoPaused, isFalse);
  });
}
