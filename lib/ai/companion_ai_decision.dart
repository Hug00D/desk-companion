enum CompanionAiMode { action, chat, clarify }

enum CompanionAiIntent {
  none,
  startPomodoro,
  pausePomodoro,
  resumePomodoro,
  stopPomodoro,
  requestBreak,
  requestFocusSummary,
  requestTimerStatus,
  reportTired,
  reportDistracted,
}

class CompanionAiDecision {
  const CompanionAiDecision({
    required this.mode,
    required this.intent,
    required this.confidence,
    required this.needsConfirmation,
    required this.confirmationText,
    required this.chatReply,
    required this.durationMinutes,
  });

  final CompanionAiMode mode;
  final CompanionAiIntent intent;
  final double confidence;
  final bool needsConfirmation;
  final String confirmationText;
  final String chatReply;
  final int? durationMinutes;

  bool get hasAction =>
      mode == CompanionAiMode.action && intent != CompanionAiIntent.none;

  factory CompanionAiDecision.fromJson(Map<String, dynamic> json) {
    final parameters = json['parameters'] is Map
        ? Map<String, dynamic>.from(json['parameters'] as Map)
        : const <String, dynamic>{};

    return CompanionAiDecision(
      mode: _modeFromString(json['mode']?.toString()),
      intent: _intentFromString(json['intent']?.toString()),
      confidence: _toDouble(json['confidence']) ?? 0,
      needsConfirmation: json['needsConfirmation'] == true,
      confirmationText: json['confirmationText']?.toString() ?? '',
      chatReply: json['chatReply']?.toString() ?? '',
      durationMinutes: _toInt(parameters['durationMinutes']),
    );
  }
}

CompanionAiMode _modeFromString(String? value) {
  switch (value) {
    case 'action':
      return CompanionAiMode.action;
    case 'clarify':
      return CompanionAiMode.clarify;
    case 'chat':
    default:
      return CompanionAiMode.chat;
  }
}

CompanionAiIntent _intentFromString(String? value) {
  switch (value) {
    case 'start_pomodoro':
      return CompanionAiIntent.startPomodoro;
    case 'pause_pomodoro':
      return CompanionAiIntent.pausePomodoro;
    case 'resume_pomodoro':
      return CompanionAiIntent.resumePomodoro;
    case 'stop_pomodoro':
      return CompanionAiIntent.stopPomodoro;
    case 'request_break':
      return CompanionAiIntent.requestBreak;
    case 'request_focus_summary':
      return CompanionAiIntent.requestFocusSummary;
    case 'request_timer_status':
      return CompanionAiIntent.requestTimerStatus;
    case 'report_tired':
      return CompanionAiIntent.reportTired;
    case 'report_distracted':
      return CompanionAiIntent.reportDistracted;
    case 'none':
    default:
      return CompanionAiIntent.none;
  }
}

double? _toDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return null;
}

int? _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}
