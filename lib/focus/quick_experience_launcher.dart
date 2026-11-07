import 'pomodoro_controller.dart';

enum QuickExperienceStartResult {
  started,
  sessionAlreadyActive,
  cameraInitializing,
  cameraUnavailable,
  calibrationInProgress,
}

/// Starts the graduation-demo quick experience through the regular Pomodoro
/// pipeline, while keeping the camera and calibration preconditions explicit.
class QuickExperienceLauncher {
  const QuickExperienceLauncher();

  static const int durationMinutes = 1;

  QuickExperienceStartResult start({
    required PomodoroController pomodoroController,
    required bool isCameraInitializing,
    required bool isUsingNativeCamera,
    required bool isCalibrating,
  }) {
    if (pomodoroController.isActive) {
      return QuickExperienceStartResult.sessionAlreadyActive;
    }
    if (isCameraInitializing) {
      return QuickExperienceStartResult.cameraInitializing;
    }
    if (!isUsingNativeCamera) {
      return QuickExperienceStartResult.cameraUnavailable;
    }
    if (isCalibrating) {
      return QuickExperienceStartResult.calibrationInProgress;
    }

    pomodoroController.start(durationMinutes: durationMinutes);
    return QuickExperienceStartResult.started;
  }
}
