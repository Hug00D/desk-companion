enum CompanionResponseSource { vision, voice }

enum CompanionResponseTone { neutral, supportive, warning, action }

class CompanionResponse {
  const CompanionResponse({
    required this.source,
    required this.tone,
    required this.message,
    this.actionLabel,
    this.shouldNotify = false,
  });

  final CompanionResponseSource source;
  final CompanionResponseTone tone;
  final String message;
  final String? actionLabel;
  final bool shouldNotify;
}
