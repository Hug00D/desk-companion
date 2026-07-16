enum AssistantMode { action, chat, clarify }

class AssistantReply {
  const AssistantReply({
    required this.mode,
    required this.message,
    this.intent,
    this.action,
    this.confidence,
    this.needsConfirmation = false,
    this.confirmationText,
    this.chatReply,
    this.parameters = const <String, dynamic>{},
    this.model,
  });

  final AssistantMode mode;
  final String message;
  final String? intent;
  final String? action;
  final double? confidence;
  final bool needsConfirmation;
  final String? confirmationText;
  final String? chatReply;
  final Map<String, dynamic> parameters;
  final String? model;

  factory AssistantReply.fromJson(Map<String, dynamic> json) {
    final chatReply = json['chatReply']?.toString();
    final confirmationText = json['confirmationText']?.toString();
    final message =
        json['message']?.toString() ?? chatReply ?? confirmationText ?? '';
    final parameters = json['parameters'] is Map
        ? Map<String, dynamic>.from(json['parameters'] as Map)
        : const <String, dynamic>{};

    return AssistantReply(
      mode: _parseMode(json['mode']?.toString()),
      message: message,
      intent: json['intent']?.toString(),
      action: json['action']?.toString(),
      confidence: _toDouble(json['confidence']),
      needsConfirmation: json['needsConfirmation'] == true,
      confirmationText: confirmationText,
      chatReply: chatReply,
      parameters: parameters,
      model: json['model']?.toString(),
    );
  }

  static AssistantMode _parseMode(String? value) {
    switch (value) {
      case 'action':
        return AssistantMode.action;
      case 'clarify':
        return AssistantMode.clarify;
      case 'chat':
      default:
        return AssistantMode.chat;
    }
  }

  static double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}

class AssistantConversationMessage {
  const AssistantConversationMessage({
    required this.role,
    required this.content,
  });

  final String role;
  final String content;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'role': role, 'content': content};
  }
}
