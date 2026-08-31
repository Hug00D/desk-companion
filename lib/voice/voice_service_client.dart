import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class VoiceServiceClient {
  VoiceServiceClient({
    http.Client? httpClient,
    String baseUrl = defaultBaseUrl,
    this.timeout = const Duration(seconds: 200),
    this.audioDownloadTimeout = const Duration(seconds: 20),
  }) : _injectedHttpClient = httpClient,
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

  final http.Client? _injectedHttpClient;
  final String baseUrl;
  final Duration timeout;
  final Duration audioDownloadTimeout;
  int _requestSequence = 0;

  String createRequestId({String source = 'voice'}) {
    _requestSequence += 1;
    return '$source-${DateTime.now().microsecondsSinceEpoch}-$_requestSequence';
  }

  Future<VoiceServiceSendResult> sendReminder({
    required String text,
    required String status,
    required String eventType,
    String source = 'vision',
    String? actionLabel,
    String? requestId,
  }) async {
    final resolvedRequestId = requestId ?? createRequestId(source: source);
    final uri = Uri.parse('$baseUrl/tts');
    final payload = <String, dynamic>{
      'requestId': resolvedRequestId,
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

    final response = await _sendWithFreshConnection(
      (client) => client.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ),
    );

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
    final spokenText = body['text']?.toString();
    final durationMsValue = body['durationMs'];
    final durationMs = durationMsValue is num
        ? durationMsValue.round()
        : int.tryParse(durationMsValue?.toString() ?? '');
    final generated =
        (mode == 'gpt_sovits' ||
            mode == 'mock_wav' ||
            mode == 'windows_tts' ||
            mode == 'cached_wav') &&
        audioPath != null &&
        audioPath.isNotEmpty &&
        audioUrl != null &&
        audioUrl.isNotEmpty;
    final audioBytes = generated
        ? await _fetchAudioBytes(audioUrl, requestId: resolvedRequestId)
        : null;

    if (kDebugMode) {
      debugPrint(
        '[VOICE][request=$resolvedRequestId] tts_response ${response.body}',
      );
      if (audioBytes != null) {
        debugPrint(
          '[VOICE][request=$resolvedRequestId] audio_validated '
          'bytes=${audioBytes.length}',
        );
      }
    }

    return VoiceServiceSendResult(
      requestId: body['requestId']?.toString() ?? resolvedRequestId,
      generated: generated && audioBytes != null && audioBytes.isNotEmpty,
      mode: mode,
      reason: body['reason']?.toString(),
      audioPath: audioPath,
      audioUrl: audioUrl,
      audioBytes: audioBytes,
      spokenText: spokenText,
      duration: durationMs == null ? null : Duration(milliseconds: durationMs),
    );
  }

  Future<Uint8List?> _fetchAudioBytes(
    String audioUrl, {
    required String requestId,
  }) async {
    final parsedAudioUri = Uri.parse(audioUrl);
    final audioUri = parsedAudioUri.hasScheme
        ? parsedAudioUri
        : Uri.parse('$baseUrl/').resolveUri(parsedAudioUri);
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt += 1) {
      try {
        final response = await _sendWithFreshConnection(
          (client) => client.get(audioUri),
          requestTimeout: audioDownloadTimeout,
        );
        if (kDebugMode) {
          debugPrint(
            '[VOICE][request=$requestId][attempt=$attempt] '
            'audio_headers_received status=${response.statusCode} '
            'length=${response.headers['x-audio-length'] ?? response.headers['content-length'] ?? 'unknown'}',
          );
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw VoiceServiceException(
            'Voice audio failed: ${response.statusCode} ${response.body}',
          );
        }
        final contentType = response.headers['content-type']?.toLowerCase();
        final isWavContentType =
            contentType != null &&
            (contentType.contains('audio/wav') ||
                contentType.contains('audio/x-wav') ||
                contentType.contains('audio/wave'));
        if (!isWavContentType) {
          throw VoiceServiceException(
            'Voice audio has invalid content type: ${contentType ?? 'missing'}',
          );
        }
        final audioBytes = response.bodyBytes;
        final expectedLength = int.tryParse(
          response.headers['x-audio-length'] ??
              response.headers['content-length'] ??
              '',
        );
        if (expectedLength != null && expectedLength != audioBytes.length) {
          throw VoiceServiceException(
            'Voice audio incomplete: received ${audioBytes.length} of '
            '$expectedLength bytes',
          );
        }
        if (audioBytes.isEmpty) {
          throw const VoiceServiceException('Voice audio response was empty');
        }
        _validateWav(audioBytes);
        return audioBytes;
      } catch (error) {
        lastError = error;
        if (attempt == 3) break;
        if (kDebugMode) {
          debugPrint(
            '[VOICE][request=$requestId][attempt=$attempt] '
            'audio_download_retry error=$error',
          );
        }
        await Future<void>.delayed(Duration(milliseconds: 250 * attempt));
      }
    }
    throw VoiceServiceException('Voice audio download failed: $lastError');
  }

  void _validateWav(Uint8List audioBytes) {
    if (audioBytes.length < 44) {
      throw VoiceServiceException(
        'Voice audio is not a complete WAV: ${audioBytes.length} bytes',
      );
    }
    final riff = ascii.decode(audioBytes.sublist(0, 4), allowInvalid: true);
    final wave = ascii.decode(audioBytes.sublist(8, 12), allowInvalid: true);
    if (riff != 'RIFF' || wave != 'WAVE') {
      throw VoiceServiceException(
        'Voice audio has invalid WAV header: RIFF=$riff WAVE=$wave',
      );
    }
    final riffPayloadLength = ByteData.sublistView(
      audioBytes,
      4,
      8,
    ).getUint32(0, Endian.little);
    final riffFileLength = riffPayloadLength + 8;
    if (riffFileLength != audioBytes.length) {
      throw VoiceServiceException(
        'Voice audio RIFF length mismatch: received ${audioBytes.length} of '
        '$riffFileLength bytes',
      );
    }
  }

  Future<VoiceServiceHealth> checkHealth({
    Duration healthTimeout = const Duration(seconds: 5),
  }) async {
    final response = await _sendWithFreshConnection(
      (client) => client.get(Uri.parse('$baseUrl/health')),
      requestTimeout: healthTimeout,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw VoiceServiceException(
        'Voice health failed: ${response.statusCode} ${response.body}',
      );
    }
    final decoded = jsonDecode(response.body);
    final body = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{};
    final gptSovitsValue = body['gptSovits'];
    final gptSovits = gptSovitsValue is Map<String, dynamic>
        ? gptSovitsValue
        : <String, dynamic>{};
    final generationValue = body['generation'];
    final generation = generationValue is Map<String, dynamic>
        ? generationValue
        : <String, dynamic>{};
    return VoiceServiceHealth(
      available: body['ok'] == true,
      gptSovitsReady: gptSovits['ready'] == true,
      generationInProgress: generation['inProgress'] == true,
      waitingRequests: (generation['waitingRequests'] as num?)?.toInt() ?? 0,
      processId: (body['processId'] as num?)?.toInt(),
    );
  }

  Future<http.Response> _sendWithFreshConnection(
    Future<http.Response> Function(http.Client client) request, {
    Duration? requestTimeout,
  }) async {
    final effectiveTimeout = requestTimeout ?? timeout;
    final injectedClient = _injectedHttpClient;
    if (injectedClient != null) {
      return request(injectedClient).timeout(effectiveTimeout);
    }

    final client = http.Client();
    try {
      return await request(client).timeout(effectiveTimeout);
    } finally {
      client.close();
    }
  }

  void close() {
    _injectedHttpClient?.close();
  }
}

class VoiceServiceSendResult {
  const VoiceServiceSendResult({
    required this.requestId,
    required this.generated,
    this.mode,
    this.reason,
    this.audioPath,
    this.audioUrl,
    this.audioBytes,
    this.spokenText,
    this.duration,
  });

  final String requestId;
  final bool generated;
  final String? mode;
  final String? reason;
  final String? audioPath;
  final String? audioUrl;
  final Uint8List? audioBytes;
  final String? spokenText;
  final Duration? duration;
}

class VoiceServiceHealth {
  const VoiceServiceHealth({
    required this.available,
    required this.gptSovitsReady,
    required this.generationInProgress,
    required this.waitingRequests,
    this.processId,
  });

  final bool available;
  final bool gptSovitsReady;
  final bool generationInProgress;
  final int waitingRequests;
  final int? processId;
}

class VoiceServiceException implements Exception {
  const VoiceServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
