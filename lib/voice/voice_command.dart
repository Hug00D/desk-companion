enum VoiceCommandType {
  startPomodoro,
  pausePomodoro,
  resumePomodoro,
  stopPomodoro,
  requestFocusSummary,
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
}
