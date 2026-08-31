import '../voice/voice_command.dart';
import 'companion_ai_decision.dart';

class CompanionAiCommandMapper {
  const CompanionAiCommandMapper();

  VoiceCommand? toVoiceCommand({
    required String sourceText,
    required CompanionAiDecision decision,
  }) {
    final duration =
        decision.durationMinutes != null && decision.durationMinutes! > 0
        ? decision.durationMinutes
        : null;

    VoiceCommandType? commandType;
    switch (decision.intent) {
      case CompanionAiIntent.startPomodoro:
        commandType = VoiceCommandType.startPomodoro;
        break;
      case CompanionAiIntent.pausePomodoro:
        commandType = VoiceCommandType.pausePomodoro;
        break;
      case CompanionAiIntent.resumePomodoro:
        commandType = VoiceCommandType.resumePomodoro;
        break;
      case CompanionAiIntent.stopPomodoro:
        commandType = VoiceCommandType.stopPomodoro;
        break;
      case CompanionAiIntent.requestBreak:
        commandType = VoiceCommandType.requestBreak;
        break;
      case CompanionAiIntent.requestFocusSummary:
        commandType = VoiceCommandType.requestFocusSummary;
        break;
      case CompanionAiIntent.requestTimerStatus:
        commandType = VoiceCommandType.requestTimerStatus;
        break;
      case CompanionAiIntent.reportTired:
        commandType = VoiceCommandType.reportTired;
        break;
      case CompanionAiIntent.reportDistracted:
        commandType = VoiceCommandType.reportDistracted;
        break;
      case CompanionAiIntent.none:
        return null;
    }

    return VoiceCommand(
      type: commandType,
      sourceText: sourceText,
      confidence: decision.confidence,
      durationMinutes: duration,
    );
  }

  bool requiresConfirmation(VoiceCommandType type) {
    switch (type) {
      case VoiceCommandType.startPomodoro:
      case VoiceCommandType.pausePomodoro:
      case VoiceCommandType.resumePomodoro:
      case VoiceCommandType.stopPomodoro:
      case VoiceCommandType.requestBreak:
        return true;
      case VoiceCommandType.requestFocusSummary:
      case VoiceCommandType.requestTimerStatus:
      case VoiceCommandType.reportTired:
      case VoiceCommandType.reportDistracted:
      case VoiceCommandType.confirmStartPomodoro:
      case VoiceCommandType.unknown:
      case VoiceCommandType.ignored:
        return false;
    }
  }

  String defaultConfirmationText(VoiceCommand command) {
    switch (command.type) {
      case VoiceCommandType.startPomodoro:
        return '要幫你開始 ${command.durationMinutes ?? 25} 分鐘番茄鐘嗎？';
      case VoiceCommandType.pausePomodoro:
        return '要先幫你暫停番茄鐘嗎？';
      case VoiceCommandType.resumePomodoro:
        return '要幫你繼續番茄鐘嗎？';
      case VoiceCommandType.stopPomodoro:
        return '要幫你停止這輪番茄鐘嗎？';
      case VoiceCommandType.requestBreak:
        return '要幫你進入休息狀態嗎？';
      case VoiceCommandType.requestFocusSummary:
      case VoiceCommandType.requestTimerStatus:
      case VoiceCommandType.reportTired:
      case VoiceCommandType.reportDistracted:
      case VoiceCommandType.confirmStartPomodoro:
      case VoiceCommandType.unknown:
      case VoiceCommandType.ignored:
        return '要我幫你執行這個動作嗎？';
    }
  }
}
