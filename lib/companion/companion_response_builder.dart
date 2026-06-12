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
          message: '偵測到持續閉眼，建議先讓眼睛休息 5 分鐘。',
          actionLabel: 'start_break',
          shouldNotify: true,
        );
      case CompanionStatus.attention:
        return const CompanionResponse(
          source: CompanionResponseSource.vision,
          tone: CompanionResponseTone.supportive,
          message: '看起來有點分神或疲倦，要不要下一輪改成 15 分鐘短專注？',
          actionLabel: 'soft_attention_reminder',
        );
      case CompanionStatus.distracted:
        return const CompanionResponse(
          source: CompanionResponseSource.vision,
          tone: CompanionResponseTone.supportive,
          message: '視線偏離了一段時間，先把注意力帶回螢幕吧。',
          actionLabel: 'head_offset_reminder',
        );
      case CompanionStatus.drowsy:
        return const CompanionResponse(
          source: CompanionResponseSource.vision,
          tone: CompanionResponseTone.supportive,
          message: '偵測到低頭打瞌睡，先抬頭休息一下。',
          actionLabel: 'drowsy_head_reminder',
          shouldNotify: true,
        );
      case CompanionStatus.postureDown:
        return const CompanionResponse(
          source: CompanionResponseSource.vision,
          tone: CompanionResponseTone.warning,
          message: '偵測到趴下睡覺，建議先休息一下再繼續。',
          actionLabel: 'posture_down_reminder',
          shouldNotify: true,
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
      case VoiceCommandType.requestTimerStatus:
        return const CompanionResponse(
          source: CompanionResponseSource.voice,
          tone: CompanionResponseTone.neutral,
          message: '我幫你看一下目前番茄鐘狀態。',
          actionLabel: 'show_timer_status',
        );
      case VoiceCommandType.reportTired:
        return const CompanionResponse(
          source: CompanionResponseSource.voice,
          tone: CompanionResponseTone.supportive,
          message: '收到，你覺得累了。我會建議先讓眼睛休息一下。',
          actionLabel: 'self_report_tired',
        );
      case VoiceCommandType.reportDistracted:
        return const CompanionResponse(
          source: CompanionResponseSource.voice,
          tone: CompanionResponseTone.supportive,
          message: '收到，你剛剛有點分心。我們可以把節奏切小一點。',
          actionLabel: 'self_report_distracted',
        );
      case VoiceCommandType.requestBreak:
        return const CompanionResponse(
          source: CompanionResponseSource.voice,
          tone: CompanionResponseTone.action,
          message: '好，可以先休息 5 分鐘，讓眼睛和注意力回來。',
          actionLabel: 'request_break',
        );
      case VoiceCommandType.confirmStartPomodoro:
        return const CompanionResponse(
          source: CompanionResponseSource.voice,
          tone: CompanionResponseTone.supportive,
          message: '我聽起來像是你想開始番茄鐘，是嗎？',
          actionLabel: 'confirm_start_pomodoro',
          shouldNotify: true,
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
