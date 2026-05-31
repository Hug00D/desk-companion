import '../vision/companion_state_evaluator.dart';
import '../voice/voice_command.dart';
import 'companion_response.dart';

class CompanionResponseBuilder {
  const CompanionResponseBuilder();

  CompanionResponse fromVision(CompanionAnalysis analysis) {
    switch (analysis.status) {
      case CompanionStatus.fatigue:
        return const CompanionResponse(
          source: CompanionResponseSource.vision,
          tone: CompanionResponseTone.warning,
          message: '偵測到持續閉眼，建議先休息一下。',
          actionLabel: 'start_break',
          shouldNotify: true,
        );
      case CompanionStatus.attention:
        return const CompanionResponse(
          source: CompanionResponseSource.vision,
          tone: CompanionResponseTone.supportive,
          message: '似乎有些疲倦了，記得留意狀態。',
          actionLabel: 'soft_attention_reminder',
        );
      case CompanionStatus.userMissing:
        return const CompanionResponse(
          source: CompanionResponseSource.vision,
          tone: CompanionResponseTone.neutral,
          message: '我暫時沒有看到你，回來後可以繼續陪你專注。',
          actionLabel: 'user_missing',
        );
      case CompanionStatus.normal:
        return const CompanionResponse(
          source: CompanionResponseSource.vision,
          tone: CompanionResponseTone.neutral,
          message: '目前狀態穩定，請保持節奏。',
        );
    }
  }

  CompanionResponse fromVoiceCommand(VoiceCommand command) {
    switch (command.type) {
      case VoiceCommandType.startPomodoro:
        final duration = command.durationMinutes ?? 25;
        return CompanionResponse(
          source: CompanionResponseSource.voice,
          tone: CompanionResponseTone.action,
          message: '好，我幫你準備 $duration 分鐘的專注時間。',
          actionLabel: 'start_pomodoro',
          shouldNotify: true,
        );
      case VoiceCommandType.pausePomodoro:
        return const CompanionResponse(
          source: CompanionResponseSource.voice,
          tone: CompanionResponseTone.action,
          message: '好，先暫停一下。',
          actionLabel: 'pause_pomodoro',
        );
      case VoiceCommandType.resumePomodoro:
        return const CompanionResponse(
          source: CompanionResponseSource.voice,
          tone: CompanionResponseTone.action,
          message: '歡迎回來，我們繼續剛剛的節奏。',
          actionLabel: 'resume_pomodoro',
        );
      case VoiceCommandType.stopPomodoro:
        return const CompanionResponse(
          source: CompanionResponseSource.voice,
          tone: CompanionResponseTone.action,
          message: '好，這輪番茄鐘先結束。',
          actionLabel: 'stop_pomodoro',
        );
      case VoiceCommandType.requestFocusSummary:
        return const CompanionResponse(
          source: CompanionResponseSource.voice,
          tone: CompanionResponseTone.action,
          message: '我可以幫你整理今天的專注狀態。',
          actionLabel: 'show_focus_summary',
        );
      case VoiceCommandType.unknown:
        return CompanionResponse(
          source: CompanionResponseSource.voice,
          tone: CompanionResponseTone.supportive,
          message: '我還不太確定你的意思，可以換個方式說嗎？',
          actionLabel: 'ask_for_clarification',
          shouldNotify:
              command.confidence != null && command.confidence! < 0.45,
        );
      case VoiceCommandType.ignored:
        return CompanionResponse(
          source: CompanionResponseSource.voice,
          tone: CompanionResponseTone.neutral,
          message: command.reason ?? '我正在等待完整語音內容。',
        );
    }
  }
}
