import 'dart:convert';
import 'dart:typed_data';

enum AssistantMode { action, chat, clarify }

class AssistantAudio {
  const AssistantAudio({
    required this.requestId,
    required this.contentType,
    required this.bytes,
    this.duration,
  });

  final String requestId;
  final String contentType;
  final Uint8List bytes;
  final Duration? duration;

  factory AssistantAudio.fromJson(Map<String, dynamic> json) {
    final durationValue = json['durationMs'];
    final durationMs = durationValue is num
        ? durationValue.round()
        : int.tryParse(durationValue?.toString() ?? '');
    return AssistantAudio(
      requestId: json['requestId']?.toString() ?? 'assistant-backend',
      contentType: json['contentType']?.toString() ?? 'audio/wav',
      bytes: base64Decode(json['base64']?.toString() ?? ''),
      duration: durationMs == null ? null : Duration(milliseconds: durationMs),
    );
  }
}

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
    this.audio,
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
  final AssistantAudio? audio;

  factory AssistantReply.fromJson(Map<String, dynamic> json) {
    final chatReply = json['chatReply']?.toString();
    final confirmationText = json['confirmationText']?.toString();
    final message =
        json['message']?.toString() ?? chatReply ?? confirmationText ?? '';
    final parameters = json['parameters'] is Map
        ? Map<String, dynamic>.from(json['parameters'] as Map)
        : const <String, dynamic>{};
    AssistantAudio? audio;
    final audioValue = json['audio'];
    if (audioValue is Map &&
        audioValue['base64']?.toString().isNotEmpty == true) {
      try {
        audio = AssistantAudio.fromJson(Map<String, dynamic>.from(audioValue));
      } on FormatException {
        audio = null;
      }
    }

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
      audio: audio,
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
