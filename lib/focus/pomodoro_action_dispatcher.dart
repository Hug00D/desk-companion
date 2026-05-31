import '../companion/companion_response.dart';
import '../voice/voice_command.dart';
import 'pomodoro_controller.dart';

class PomodoroActionResult {
  const PomodoroActionResult({
    required this.response,
    required this.shouldStartTimer,
    required this.shouldStopTimer,
  });

  final CompanionResponse response;
  final bool shouldStartTimer;
  final bool shouldStopTimer;
}

class PomodoroActionDispatcher {
  const PomodoroActionDispatcher();

  PomodoroActionResult dispatch({
    required VoiceCommand command,
    required PomodoroController controller,
  }) {
    switch (command.type) {
      case VoiceCommandType.startPomodoro:
        return _start(command, controller);
      case VoiceCommandType.pausePomodoro:
        return _pause(controller);
      case VoiceCommandType.resumePomodoro:
        return _resume(controller);
      case VoiceCommandType.stopPomodoro:
        return _stop(controller);
      case VoiceCommandType.requestFocusSummary:
        return const PomodoroActionResult(
          response: CompanionResponse(
            source: CompanionResponseSource.voice,
            tone: CompanionResponseTone.action,
            message: '我可以幫你整理今天的專注狀態。',
            actionLabel: 'show_focus_summary',
          ),
          shouldStartTimer: false,
          shouldStopTimer: false,
        );
      case VoiceCommandType.unknown:
        return PomodoroActionResult(
          response: CompanionResponse(
            source: CompanionResponseSource.voice,
            tone: CompanionResponseTone.supportive,
            message: '我還不太確定你的意思，可以換個方式說嗎？',
            actionLabel: 'ask_for_clarification',
            shouldNotify:
                command.confidence != null && command.confidence! < 0.45,
          ),
          shouldStartTimer: false,
          shouldStopTimer: false,
        );
      case VoiceCommandType.ignored:
        return PomodoroActionResult(
          response: CompanionResponse(
            source: CompanionResponseSource.voice,
            tone: CompanionResponseTone.neutral,
            message: command.reason ?? '我正在等待完整語音內容。',
          ),
          shouldStartTimer: false,
          shouldStopTimer: false,
        );
    }
  }

  PomodoroActionResult _start(
    VoiceCommand command,
    PomodoroController controller,
  ) {
    final duration = command.durationMinutes ?? 25;

    if (controller.status == PomodoroStatus.running) {
      return PomodoroActionResult(
        response: CompanionResponse(
          source: CompanionResponseSource.voice,
          tone: CompanionResponseTone.supportive,
          message: '番茄鐘已經在進行中，目前還剩 ${controller.formattedRemaining}。',
          actionLabel: 'pomodoro_already_running',
        ),
        shouldStartTimer: false,
        shouldStopTimer: false,
      );
    }

    controller.start(durationMinutes: duration);
    return PomodoroActionResult(
      response: CompanionResponse(
        source: CompanionResponseSource.voice,
        tone: CompanionResponseTone.action,
        message: '好，我幫你準備 $duration 分鐘的專注時間。',
        actionLabel: 'start_pomodoro',
        shouldNotify: true,
      ),
      shouldStartTimer: true,
      shouldStopTimer: false,
    );
  }

  PomodoroActionResult _pause(PomodoroController controller) {
    if (controller.status == PomodoroStatus.idle ||
        controller.status == PomodoroStatus.completed) {
      return const PomodoroActionResult(
        response: CompanionResponse(
          source: CompanionResponseSource.voice,
          tone: CompanionResponseTone.supportive,
          message: '目前沒有正在進行的番茄鐘可以暫停。',
          actionLabel: 'pause_rejected_no_active_pomodoro',
        ),
        shouldStartTimer: false,
        shouldStopTimer: false,
      );
    }

    if (controller.status == PomodoroStatus.paused) {
      return const PomodoroActionResult(
        response: CompanionResponse(
          source: CompanionResponseSource.voice,
          tone: CompanionResponseTone.supportive,
          message: '番茄鐘已經暫停了。',
          actionLabel: 'pause_rejected_already_paused',
        ),
        shouldStartTimer: false,
        shouldStopTimer: false,
      );
    }

    controller.pause();
    return const PomodoroActionResult(
      response: CompanionResponse(
        source: CompanionResponseSource.voice,
        tone: CompanionResponseTone.action,
        message: '好，先暫停一下。',
        actionLabel: 'pause_pomodoro',
      ),
      shouldStartTimer: false,
      shouldStopTimer: false,
    );
  }

  PomodoroActionResult _resume(PomodoroController controller) {
    if (controller.status == PomodoroStatus.idle ||
        controller.status == PomodoroStatus.completed) {
      return const PomodoroActionResult(
        response: CompanionResponse(
          source: CompanionResponseSource.voice,
          tone: CompanionResponseTone.supportive,
          message: '目前沒有暫停中的番茄鐘可以繼續。',
          actionLabel: 'resume_rejected_no_paused_pomodoro',
        ),
        shouldStartTimer: false,
        shouldStopTimer: false,
      );
    }

    if (controller.status == PomodoroStatus.running) {
      return PomodoroActionResult(
        response: CompanionResponse(
          source: CompanionResponseSource.voice,
          tone: CompanionResponseTone.supportive,
          message: '番茄鐘已經在進行中，目前還剩 ${controller.formattedRemaining}。',
          actionLabel: 'resume_rejected_already_running',
        ),
        shouldStartTimer: false,
        shouldStopTimer: false,
      );
    }

    controller.resume();
    return const PomodoroActionResult(
      response: CompanionResponse(
        source: CompanionResponseSource.voice,
        tone: CompanionResponseTone.action,
        message: '歡迎回來，我們繼續剛剛的節奏。',
        actionLabel: 'resume_pomodoro',
      ),
      shouldStartTimer: true,
      shouldStopTimer: false,
    );
  }

  PomodoroActionResult _stop(PomodoroController controller) {
    if (controller.status == PomodoroStatus.idle ||
        controller.status == PomodoroStatus.completed) {
      return const PomodoroActionResult(
        response: CompanionResponse(
          source: CompanionResponseSource.voice,
          tone: CompanionResponseTone.supportive,
          message: '目前沒有正在進行的番茄鐘可以中止。',
          actionLabel: 'stop_rejected_no_active_pomodoro',
        ),
        shouldStartTimer: false,
        shouldStopTimer: false,
      );
    }

    controller.stop();
    return const PomodoroActionResult(
      response: CompanionResponse(
        source: CompanionResponseSource.voice,
        tone: CompanionResponseTone.action,
        message: '好，這輪番茄鐘先結束。',
        actionLabel: 'stop_pomodoro',
      ),
      shouldStartTimer: false,
      shouldStopTimer: true,
    );
  }
}
