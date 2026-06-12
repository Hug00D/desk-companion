enum VoiceEventType { partial, finalResult, error }

class VoiceRecognitionResult {
  const VoiceRecognitionResult({
    required this.sessionId,
    required this.eventType,
    required this.timestampMs,
    this.caseId,
    this.transcript,
    this.formattedTranscript,
    this.isFinal = false,
    this.candidates = const [],
    this.audio,
    this.language,
    this.recognitionParts = const [],
    this.alternatives = const [],
    this.error,
  });

  final String sessionId;
  final VoiceEventType eventType;
  final int timestampMs;
  final String? caseId;
  final String? transcript;
  final String? formattedTranscript;
  final bool isFinal;
  final List<VoiceCandidate> candidates;
  final VoiceAudioInfo? audio;
  final VoiceLanguageInfo? language;
  final List<VoiceRecognitionPart> recognitionParts;
  final List<VoiceAlternativeSpan> alternatives;
  final VoiceRecognitionError? error;

  bool get hasError => eventType == VoiceEventType.error || error != null;

  String get bestText {
    if (formattedTranscript != null && formattedTranscript!.isNotEmpty) {
      return formattedTranscript!;
    }
    if (transcript != null && transcript!.isNotEmpty) {
      return transcript!;
    }
    if (candidates.isNotEmpty) return candidates.first.text;
    return '';
  }

  double? get bestConfidence {
    if (candidates.isEmpty) return null;
    return candidates.first.confidence;
  }

  factory VoiceRecognitionResult.fromJson(Map<String, dynamic> json) {
    return VoiceRecognitionResult(
      caseId: json['caseId']?.toString(),
      sessionId: json['sessionId']?.toString() ?? '',
      eventType: _eventTypeFromString(json['eventType']?.toString()),
      timestampMs: _toInt(json['timestampMs']) ?? 0,
      transcript: json['transcript']?.toString(),
      formattedTranscript: json['formattedTranscript']?.toString(),
      isFinal: json['isFinal'] == true,
      candidates: _listOfMaps(
        json['candidates'],
      ).map(VoiceCandidate.fromJson).toList(),
      audio: json['audio'] is Map
          ? VoiceAudioInfo.fromJson(Map<String, dynamic>.from(json['audio']))
          : null,
      language: json['language'] is Map
          ? VoiceLanguageInfo.fromJson(
              Map<String, dynamic>.from(json['language']),
            )
          : null,
      recognitionParts: _listOfMaps(
        json['recognitionParts'],
      ).map(VoiceRecognitionPart.fromJson).toList(),
      alternatives: _listOfMaps(
        json['alternatives'],
      ).map(VoiceAlternativeSpan.fromJson).toList(),
      error: json['error'] is Map
          ? VoiceRecognitionError.fromJson(
              Map<String, dynamic>.from(json['error']),
            )
          : null,
    );
  }

  static VoiceEventType _eventTypeFromString(String? value) {
    switch (value) {
      case 'partial':
        return VoiceEventType.partial;
      case 'error':
        return VoiceEventType.error;
      case 'final':
      default:
        return VoiceEventType.finalResult;
    }
  }
}

class VoiceCandidate {
  const VoiceCandidate({required this.text, this.confidence});

  final String text;
  final double? confidence;

  factory VoiceCandidate.fromJson(Map<String, dynamic> json) {
    return VoiceCandidate(
      text: json['text']?.toString() ?? '',
      confidence: _toDouble(json['confidence']),
    );
  }
}

class VoiceAudioInfo {
  const VoiceAudioInfo({this.rmsDb, this.isSpeechDetected = false});

  final double? rmsDb;
  final bool isSpeechDetected;

  factory VoiceAudioInfo.fromJson(Map<String, dynamic> json) {
    return VoiceAudioInfo(
      rmsDb: _toDouble(json['rmsDb']),
      isSpeechDetected: json['isSpeechDetected'] == true,
    );
  }
}

class VoiceLanguageInfo {
  const VoiceLanguageInfo({
    this.tag,
    this.confidenceLevel,
    this.alternatives = const [],
  });

  final String? tag;
  final String? confidenceLevel;
  final List<String> alternatives;

  factory VoiceLanguageInfo.fromJson(Map<String, dynamic> json) {
    return VoiceLanguageInfo(
      tag: json['tag']?.toString(),
      confidenceLevel: json['confidenceLevel']?.toString(),
      alternatives: _listOfValues(
        json['alternatives'],
      ).map((value) => value.toString()).toList(),
    );
  }
}

class VoiceRecognitionPart {
  const VoiceRecognitionPart({
    required this.text,
    this.formattedText,
    this.timestampMs,
    this.confidence,
  });

  final String text;
  final String? formattedText;
  final int? timestampMs;
  final double? confidence;

  factory VoiceRecognitionPart.fromJson(Map<String, dynamic> json) {
    return VoiceRecognitionPart(
      text: json['text']?.toString() ?? '',
      formattedText: json['formattedText']?.toString(),
      timestampMs: _toInt(json['timestampMs']),
      confidence: _toDouble(json['confidence']),
    );
  }
}

class VoiceAlternativeSpan {
  const VoiceAlternativeSpan({
    required this.startIndex,
    required this.endIndex,
    this.texts = const [],
  });

  final int startIndex;
  final int endIndex;
  final List<String> texts;

  factory VoiceAlternativeSpan.fromJson(Map<String, dynamic> json) {
    return VoiceAlternativeSpan(
      startIndex: _toInt(json['startIndex']) ?? 0,
      endIndex: _toInt(json['endIndex']) ?? 0,
      texts: _listOfValues(
        json['texts'],
      ).map((value) => value.toString()).toList(),
    );
  }
}

class VoiceRecognitionError {
  const VoiceRecognitionError({required this.code, required this.message});

  final String code;
  final String message;

  factory VoiceRecognitionError.fromJson(Map<String, dynamic> json) {
    return VoiceRecognitionError(
      code: json['code']?.toString() ?? 'UNKNOWN',
      message: json['message']?.toString() ?? 'Unknown voice error.',
    );
  }
}

List<Map<String, dynamic>> _listOfMaps(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

List<dynamic> _listOfValues(dynamic value) {
  if (value is List) return value;
  return const [];
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
