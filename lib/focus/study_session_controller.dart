import '../vision/vision_event.dart';
import '../vision/vision_event_tracker.dart';
import '../voice/voice_command.dart';
import 'pomodoro_controller.dart';

class StudySessionController {
  DateTime? startedAt;
  DateTime? _lastVisionSampleAt;

  Duration focusedDuration = Duration.zero;
  Duration awayDuration = Duration.zero;

  int attentionWarningCount = 0;
  int fatigueEventCount = 0;
  int partialUserDetectedCount = 0;
  int userAwayCount = 0;
  int userReturnedCount = 0;

  int pomodoroStartedCount = 0;
  int pomodoroPausedCount = 0;
  int pomodoroResumedCount = 0;
  int pomodoroStoppedCount = 0;
  int pomodoroCompletedCount = 0;

  int tiredSelfReportCount = 0;
  int distractedSelfReportCount = 0;
  int breakRequestCount = 0;
  int unknownVoiceCommandCount = 0;
  int lowConfidenceConfirmationCount = 0;

  bool get hasStarted => startedAt != null;

  void ensureStarted({DateTime? now}) {
    startedAt ??= now ?? DateTime.now();
  }

  void recordVisionTrackingResult(
    VisionEventTrackingResult trackingResult, {
    required bool isStudying,
    DateTime? now,
  }) {
    final timestamp = now ?? trackingResult.event.timestamp;
    ensureStarted(now: timestamp);
    _recordVisionDuration(trackingResult, isStudying, timestamp);

    if (!trackingResult.shouldPersist) return;

    switch (trackingResult.event.type) {
      case VisionEventType.attentionWarning:
        attentionWarningCount += 1;
        break;
      case VisionEventType.fatigueDetected:
        fatigueEventCount += 1;
        break;
      case VisionEventType.partialUserDetected:
        partialUserDetectedCount += 1;
        break;
      case VisionEventType.userAway:
        userAwayCount += 1;
        break;
      case VisionEventType.userReturned:
        userReturnedCount += 1;
        break;
      case VisionEventType.normal:
        break;
    }
  }

  void recordVoiceCommand(VoiceCommand command) {
    ensureStarted();

    switch (command.type) {
      case VoiceCommandType.reportTired:
        tiredSelfReportCount += 1;
        break;
      case VoiceCommandType.reportDistracted:
        distractedSelfReportCount += 1;
        break;
      case VoiceCommandType.requestBreak:
        breakRequestCount += 1;
        break;
      case VoiceCommandType.confirmStartPomodoro:
        lowConfidenceConfirmationCount += 1;
        break;
      case VoiceCommandType.unknown:
        unknownVoiceCommandCount += 1;
        break;
      case VoiceCommandType.startPomodoro:
      case VoiceCommandType.pausePomodoro:
      case VoiceCommandType.resumePomodoro:
      case VoiceCommandType.stopPomodoro:
      case VoiceCommandType.requestFocusSummary:
      case VoiceCommandType.requestTimerStatus:
      case VoiceCommandType.ignored:
        break;
    }
  }

  void recordPomodoroStarted() {
    ensureStarted();
    pomodoroStartedCount += 1;
  }

  void recordPomodoroPaused() {
    ensureStarted();
    pomodoroPausedCount += 1;
  }

  void recordPomodoroResumed() {
    ensureStarted();
    pomodoroResumedCount += 1;
  }

  void recordPomodoroStopped() {
    ensureStarted();
    pomodoroStoppedCount += 1;
  }

  void recordPomodoroCompleted() {
    ensureStarted();
    pomodoroCompletedCount += 1;
  }

  String buildSummary(PomodoroController pomodoroController) {
    final focusText = _formatDuration(focusedDuration);
    final awayText = _formatDuration(awayDuration);
    final timerText = pomodoroController.isActive
        ? '目前番茄鐘還剩 ${pomodoroController.formattedRemaining}'
        : '目前沒有進行中的番茄鐘';

    return '今天目前專注 $focusText，離開 $awayText。'
        '疲勞提醒 $fatigueEventCount 次，注意力提醒 $attentionWarningCount 次，'
        '番茄鐘完成 $pomodoroCompletedCount 輪、暫停 $pomodoroPausedCount 次。$timerText。';
  }

  String buildTimerStatus(PomodoroController pomodoroController) {
    if (pomodoroController.status == PomodoroStatus.running) {
      return '番茄鐘正在進行中，目前還剩 ${pomodoroController.formattedRemaining}。';
    }
    if (pomodoroController.status == PomodoroStatus.paused) {
      return '番茄鐘目前暫停中，還剩 ${pomodoroController.formattedRemaining}。';
    }
    if (pomodoroController.status == PomodoroStatus.completed) {
      return '這輪番茄鐘已經完成了，可以休息一下。';
    }
    return '目前沒有進行中的番茄鐘。';
  }

  void _recordVisionDuration(
    VisionEventTrackingResult trackingResult,
    bool isStudying,
    DateTime timestamp,
  ) {
    final lastSampleAt = _lastVisionSampleAt;
    _lastVisionSampleAt = timestamp;
    if (lastSampleAt == null) return;

    final delta = timestamp.difference(lastSampleAt);
    if (delta <= Duration.zero || delta > const Duration(seconds: 5)) return;

    final isAway =
        trackingResult.isStable &&
        trackingResult.event.type == VisionEventType.userAway;
    if (isAway) {
      awayDuration += delta;
      return;
    }

    if (isStudying && trackingResult.isStable) {
      focusedDuration += delta;
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    if (minutes == 0) return '$seconds 秒';
    if (seconds == 0) return '$minutes 分鐘';
    return '$minutes 分 $seconds 秒';
  }
}
