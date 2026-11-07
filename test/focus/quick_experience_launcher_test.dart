import 'package:desk_companion/focus/pomodoro_controller.dart';
import 'package:desk_companion/focus/quick_experience_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const launcher = QuickExperienceLauncher();
  final controller = PomodoroController();

  setUp(controller.stop);
  tearDown(controller.stop);

  test('ready camera starts a real one-minute Pomodoro', () {
    final result = launcher.start(
      pomodoroController: controller,
      isCameraInitializing: false,
      isUsingNativeCamera: true,
      isCalibrating: false,
    );

    expect(result, QuickExperienceStartResult.started);
    expect(controller.status, PomodoroStatus.running);
    expect(controller.totalDuration, const Duration(minutes: 1));
    expect(controller.remaining, const Duration(minutes: 1));
  });

  test('an active session is never replaced by the quick experience', () {
    controller.start(durationMinutes: 25);

    final result = launcher.start(
      pomodoroController: controller,
      isCameraInitializing: false,
      isUsingNativeCamera: true,
      isCalibrating: false,
    );

    expect(result, QuickExperienceStartResult.sessionAlreadyActive);
    expect(controller.totalDuration, const Duration(minutes: 25));
  });

  test('camera and calibration preconditions block starting', () {
    expect(
      launcher.start(
        pomodoroController: controller,
        isCameraInitializing: true,
        isUsingNativeCamera: false,
        isCalibrating: true,
      ),
      QuickExperienceStartResult.cameraInitializing,
    );
    expect(controller.status, PomodoroStatus.idle);

    expect(
      launcher.start(
        pomodoroController: controller,
        isCameraInitializing: false,
        isUsingNativeCamera: false,
        isCalibrating: false,
      ),
      QuickExperienceStartResult.cameraUnavailable,
    );
    expect(controller.status, PomodoroStatus.idle);

    expect(
      launcher.start(
        pomodoroController: controller,
        isCameraInitializing: false,
        isUsingNativeCamera: true,
        isCalibrating: true,
      ),
      QuickExperienceStartResult.calibrationInProgress,
    );
    expect(controller.status, PomodoroStatus.idle);
  });

  test('a completed session can immediately start the next round', () {
    controller.status = PomodoroStatus.completed;
    controller.totalDuration = const Duration(minutes: 25);

    final result = launcher.start(
      pomodoroController: controller,
      isCameraInitializing: false,
      isUsingNativeCamera: true,
      isCalibrating: false,
    );

    expect(result, QuickExperienceStartResult.started);
    expect(controller.status, PomodoroStatus.running);
    expect(controller.totalDuration, const Duration(minutes: 1));
  });
}
