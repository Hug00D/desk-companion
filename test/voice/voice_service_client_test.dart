import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:desk_companion/voice/voice_service_client.dart';

Uint8List _fakeWav({int payloadBytes = 8}) {
  final bytes = Uint8List(44 + payloadBytes);
  bytes.setRange(0, 4, ascii.encode('RIFF'));
  bytes.setRange(8, 12, ascii.encode('WAVE'));
  ByteData.sublistView(
    bytes,
    4,
    8,
  ).setUint32(0, bytes.length - 8, Endian.little);
  return bytes;
}

void main() {
  test('downloads one-shot audio returned by the voice service', () async {
    final expectedAudio = _fakeWav();
    final requests = <http.Request>[];
    final client = VoiceServiceClient(
      baseUrl: 'http://voice.test:8001/',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method == 'POST' && request.url.path == '/tts') {
          final payload = jsonDecode(request.body) as Map<String, dynamic>;
          expect(payload['text'], '早安，今天一起加油。');
          expect(payload['source'], 'assistant');
          expect(payload['eventType'], 'assistant.chat_reply');
          expect(payload['requestId'], 'test-request-1');
          return http.Response(
            jsonEncode(<String, dynamic>{
              'requestId': 'test-request-1',
              'mode': 'gpt_sovits',
              'audioPath': '/tmp/voice_once.wav',
              'audioUrl': '/audio/voice_once.wav',
              'text': '早安，今天一起加油。',
              'durationMs': 2400,
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET' &&
            request.url.path == '/audio/voice_once.wav') {
          return http.Response.bytes(
            expectedAudio,
            200,
            headers: <String, String>{
              'content-type': 'audio/wav',
              'x-audio-length': '${expectedAudio.length}',
            },
          );
        }
        return http.Response('not found', 404);
      }),
    );

    final result = await client.sendReminder(
      text: '早安，今天一起加油。',
      status: 'assistant_chat',
      eventType: 'assistant.chat_reply',
      source: 'assistant',
      requestId: 'test-request-1',
    );

    expect(result.requestId, 'test-request-1');
    expect(result.generated, isTrue);
    expect(result.audioBytes, expectedAudio);
    expect(result.spokenText, '早安，今天一起加油。');
    expect(result.duration, const Duration(milliseconds: 2400));
    expect(requests, hasLength(2));
    client.close();
  });

  test('throws when synthesis returns an error', () async {
    final client = VoiceServiceClient(
      baseUrl: 'http://voice.test:8001',
      httpClient: MockClient(
        (_) async => http.Response('generation busy', 429),
      ),
    );

    expect(
      () => client.sendReminder(
        text: '測試',
        status: 'assistant_chat',
        eventType: 'assistant.chat_reply',
        source: 'assistant',
      ),
      throwsA(isA<VoiceServiceException>()),
    );
    client.close();
  });

  test('retries an interrupted one-shot audio download', () async {
    var audioRequestCount = 0;
    final expectedAudio = _fakeWav(payloadBytes: 12);
    final client = VoiceServiceClient(
      baseUrl: 'http://voice.test:8001',
      httpClient: MockClient((request) async {
        if (request.method == 'POST') {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'mode': 'gpt_sovits',
              'audioPath': '/tmp/voice_retry.wav',
              'audioUrl': 'http://voice.test:8001/audio/voice_retry.wav',
            }),
            200,
          );
        }
        audioRequestCount += 1;
        if (audioRequestCount == 1) {
          throw http.ClientException('connection interrupted');
        }
        return http.Response.bytes(
          expectedAudio,
          200,
          headers: <String, String>{
            'content-type': 'audio/wav',
            'x-audio-length': '${expectedAudio.length}',
          },
        );
      }),
    );

    final result = await client.sendReminder(
      text: '再試一次',
      status: 'assistant_chat',
      eventType: 'assistant.chat_reply',
      source: 'assistant',
    );

    expect(audioRequestCount, 2);
    expect(result.generated, isTrue);
    expect(result.audioBytes, expectedAudio);
    client.close();
  });

  test('rejects audio when content length does not match', () async {
    var audioRequestCount = 0;
    final client = VoiceServiceClient(
      baseUrl: 'http://voice.test:8001',
      httpClient: MockClient((request) async {
        if (request.method == 'POST') {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'mode': 'gpt_sovits',
              'audioPath': '/tmp/voice_incomplete.wav',
              'audioUrl': '/audio/voice_incomplete.wav',
            }),
            200,
          );
        }
        audioRequestCount += 1;
        return http.Response.bytes(
          <int>[82, 73, 70, 70],
          200,
          headers: const <String, String>{
            'content-type': 'audio/wav',
            'x-audio-length': '20',
          },
        );
      }),
    );

    await expectLater(
      client.sendReminder(
        text: '測試不完整音檔',
        status: 'assistant_chat',
        eventType: 'assistant.chat_reply',
        source: 'assistant',
      ),
      throwsA(
        isA<VoiceServiceException>().having(
          (error) => error.message,
          'message',
          contains('Voice audio incomplete'),
        ),
      ),
    );
    expect(audioRequestCount, 3);
    client.close();
  });

  test('rejects a response without a WAV header', () async {
    final invalidAudio = Uint8List(48);
    final client = VoiceServiceClient(
      baseUrl: 'http://voice.test:8001',
      httpClient: MockClient((request) async {
        if (request.method == 'POST') {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'mode': 'gpt_sovits',
              'audioPath': '/tmp/voice_invalid.wav',
              'audioUrl': '/audio/voice_invalid.wav',
            }),
            200,
          );
        }
        return http.Response.bytes(
          invalidAudio,
          200,
          headers: <String, String>{
            'content-type': 'audio/wav',
            'content-length': '${invalidAudio.length}',
          },
        );
      }),
    );

    await expectLater(
      client.sendReminder(
        text: '測試錯誤格式',
        status: 'assistant_chat',
        eventType: 'assistant.chat_reply',
        source: 'assistant',
      ),
      throwsA(
        isA<VoiceServiceException>().having(
          (error) => error.message,
          'message',
          contains('invalid WAV header'),
        ),
      ),
    );
    client.close();
  });

  test('reports voice service and GPT-SoVITS health', () async {
    final client = VoiceServiceClient(
      baseUrl: 'http://voice.test:8001',
      httpClient: MockClient(
        (request) async => http.Response(
          jsonEncode(<String, dynamic>{
            'ok': true,
            'processId': 123,
            'gptSovits': <String, dynamic>{'ready': true},
            'generation': <String, dynamic>{
              'inProgress': false,
              'waitingRequests': 2,
            },
          }),
          200,
        ),
      ),
    );

    final health = await client.checkHealth();

    expect(health.available, isTrue);
    expect(health.gptSovitsReady, isTrue);
    expect(health.waitingRequests, 2);
    expect(health.processId, 123);
    client.close();
  });
}
