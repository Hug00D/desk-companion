import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class VoiceServiceClient {
  VoiceServiceClient({
    http.Client? httpClient,
    String baseUrl = defaultBaseUrl,
    this.timeout = const Duration(seconds: 8),
  }) : _httpClient = httpClient ?? http.Client(),
       baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl;

  static const defaultBaseUrl = String.fromEnvironment(
    'VOICE_SERVICE_URL',
    defaultValue: 'http://10.0.2.2:8001',
  );
  static const defaultVoiceName = String.fromEnvironment('VOICE_SERVICE_VOICE');
  static const defaultVoiceCulture = String.fromEnvironment(
    'VOICE_SERVICE_VOICE_CULTURE',
  );

  final http.Client _httpClient;
  final String baseUrl;
  final Duration timeout;

  Future<VoiceServiceSendResult> sendReminder({
    required String text,
    required String status,
    required String eventType,
    String source = 'vision',
    String? actionLabel,
  }) async {
    final uri = Uri.parse('$baseUrl/tts');
    final payload = <String, dynamic>{
      'text': text,
      'source': source,
      'status': status,
      'eventType': eventType,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };
    if (defaultVoiceName.isNotEmpty) {
      payload['voiceName'] = defaultVoiceName;
    }
    if (defaultVoiceCulture.isNotEmpty) {
      payload['voiceCulture'] = defaultVoiceCulture;
    }
    if (actionLabel != null) {
      payload['actionLabel'] = actionLabel;
    }

    final response = await _httpClient
        .post(
          uri,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw VoiceServiceException(
        'Voice service failed: ${response.statusCode} ${response.body}',
      );
    }

    final decodedBody = jsonDecode(response.body);
    final body = decodedBody is Map<String, dynamic>
        ? decodedBody
        : <String, dynamic>{};
    final mode = body['mode']?.toString();
    final audioPath = body['audioPath']?.toString();
    final audioUrl = body['audioUrl']?.toString();
    final generated =
        (mode == 'mock_wav' || mode == 'windows_tts' || mode == 'cached_wav') &&
        audioPath != null &&
        audioPath.isNotEmpty &&
        audioUrl != null &&
        audioUrl.isNotEmpty;
    final audioBytes = generated ? await _fetchAudioBytes(audioUrl) : null;

    if (kDebugMode) {
      debugPrint('Voice service response: ${response.body}');
      if (audioBytes != null) {
        debugPrint('Voice service audio bytes: ${audioBytes.length}');
      }
    }

    return VoiceServiceSendResult(
      generated: generated && audioBytes != null && audioBytes.isNotEmpty,
      mode: mode,
      reason: body['reason']?.toString(),
      audioPath: audioPath,
      audioUrl: audioUrl,
      audioBytes: audioBytes,
    );
  }

  Future<Uint8List?> _fetchAudioBytes(String audioUrl) async {
    final response = await _httpClient
        .get(Uri.parse(audioUrl))
        .timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw VoiceServiceException(
        'Voice audio failed: ${response.statusCode} ${response.body}',
      );
    }
    return response.bodyBytes;
  }

  void close() {
    _httpClient.close();
  }
}

class VoiceServiceSendResult {
  const VoiceServiceSendResult({
    required this.generated,
    this.mode,
    this.reason,
    this.audioPath,
    this.audioUrl,
    this.audioBytes,
  });

  final bool generated;
  final String? mode;
  final String? reason;
  final String? audioPath;
  final String? audioUrl;
  final Uint8List? audioBytes;
}

class VoiceServiceException implements Exception {
  const VoiceServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
