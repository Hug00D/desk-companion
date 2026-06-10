import 'package:flutter/services.dart';

class VoiceChannel {
  static const MethodChannel _channel = MethodChannel(
    'com.example.desk_companion/voice_channel',
  );

  static Future<String> formatVoiceResult({
    required String transcript,
    String? formattedTranscript,
    String source = 'android',
    String caseId = 'voice_result',
    String? sessionId,
    double? confidence,
    double? rmsDb,
    bool? isSpeechDetected,
    String languageTag = 'zh-TW',
    String languageConfidenceLevel = 'confident',
  }) async {
    final result = await _channel.invokeMethod<String>('formatVoiceResult', {
      'transcript': transcript,
      'formattedTranscript': formattedTranscript,
      'source': source,
      'caseId': caseId,
      'sessionId': sessionId,
      'confidence': confidence,
      'rmsDb': rmsDb,
      'isSpeechDetected': isSpeechDetected,
      'languageTag': languageTag,
      'languageConfidenceLevel': languageConfidenceLevel,
    });

    if (result == null) {
      throw StateError('Voice formatter returned null.');
    }
    return result;
  }
}
