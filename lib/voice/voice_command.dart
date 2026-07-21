enum VoiceCommandType {
  startPomodoro,
  pausePomodoro,
  resumePomodoro,
  stopPomodoro,
  requestFocusSummary,
  requestTimerStatus,
  reportTired,
  reportDistracted,
  requestBreak,
  confirmStartPomodoro,
  unknown,
  ignored,
}

class VoiceCommand {
  const VoiceCommand({
    required this.type,
    required this.sourceText,
    this.confidence,
    this.durationMinutes,
    this.reason,
  });

  final VoiceCommandType type;
  final String sourceText;
  final double? confidence;
  final int? durationMinutes;
  final String? reason;

  bool get isActionable =>
      type != VoiceCommandType.unknown && type != VoiceCommandType.ignored;

  Map<String, dynamic> toJson({bool includeSourceText = true}) {
    return <String, dynamic>{
      'type': type.name,
      if (includeSourceText) 'sourceText': sourceText,
      if (confidence != null) 'confidence': confidence,
      if (durationMinutes != null) 'durationMinutes': durationMinutes,
      if (reason != null) 'reason': reason,
      'isActionable': isActionable,
    };
  }
}
