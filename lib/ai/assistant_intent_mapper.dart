import '../voice/voice_command.dart';

class AssistantIntentMapper {
  const AssistantIntentMapper();

  VoiceCommand? toVoiceCommand({
    required String? intent,
    required String sourceText,
    double? confidence,
    Map<String, dynamic> parameters = const <String, dynamic>{},
  }) {
    final type = _toVoiceCommandType(intent);
    if (type == null) return null;

    return VoiceCommand(
      type: type,
      sourceText: sourceText,
      confidence: confidence,
      durationMinutes: _durationMinutes(parameters),
      reason: 'Assistant decide intent: $intent',
    );
  }

  VoiceCommandType? _toVoiceCommandType(String? intent) {
    switch (intent) {
      case 'start_pomodoro':
        return VoiceCommandType.startPomodoro;
      case 'pause_pomodoro':
        return VoiceCommandType.pausePomodoro;
      case 'resume_pomodoro':
        return VoiceCommandType.resumePomodoro;
      case 'stop_pomodoro':
        return VoiceCommandType.stopPomodoro;
      case 'show_focus_summary':
        return VoiceCommandType.requestFocusSummary;
      case 'show_timer_status':
        return VoiceCommandType.requestTimerStatus;
      case 'request_break':
        return VoiceCommandType.requestBreak;
      case 'report_tired':
        return VoiceCommandType.reportTired;
      case 'report_distracted':
        return VoiceCommandType.reportDistracted;
      default:
        return null;
    }
  }

  int? _durationMinutes(Map<String, dynamic> parameters) {
    final value = parameters['durationMinutes'];
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '');
  }
}
