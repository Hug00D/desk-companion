import 'dart:convert';

import 'package:desk_companion/api/api_client.dart';
import 'package:desk_companion/api/assistant_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'chat requests natural companionship without forced pomodoro advice',
    () async {
      late Map<String, dynamic> requestBody;
      final api = AssistantApi(
        ApiClient(
          baseUrl: 'http://assistant.test/api/v1',
          httpClient: MockClient((request) async {
            requestBody = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode(<String, dynamic>{
                'mode': 'chat',
                'message': '那我們來聊點有趣的吧。',
                'chatReply': '那我們來聊點有趣的吧。',
                'audio': <String, dynamic>{
                  'requestId': 'assistant-123',
                  'contentType': 'audio/wav',
                  'base64': base64Encode(<int>[
                    ...ascii.encode('RIFF'),
                    0,
                    0,
                    0,
                    0,
                    ...ascii.encode('WAVE'),
                  ]),
                  'durationMs': 1200,
                },
              }),
              200,
              headers: const <String, String>{
                'content-type': 'application/json',
              },
            );
          }),
        ),
      );

      final reply = await api.chat(message: '我今天很無聊');

      final sentMessage = requestBody['message'] as String;
      expect(sentMessage, startsWith('我今天很無聊'));
      expect(sentMessage, contains('只能使用繁體中文'));
      expect(sentMessage, contains('禁止使用英文字母'));
      expect(sentMessage, contains('確保整段內容沒有任何英文'));
      expect(sentMessage, contains('否則不要提到番茄鐘'));
      expect(reply.chatReply, '那我們來聊點有趣的吧。');
      expect(reply.audio?.requestId, 'assistant-123');
      expect(reply.audio?.contentType, 'audio/wav');
      expect(reply.audio?.duration, const Duration(milliseconds: 1200));
      expect(reply.audio?.bytes, isNotEmpty);
    },
  );

  test('invalid bundled audio falls back to a text-only reply', () async {
    final api = AssistantApi(
      ApiClient(
        baseUrl: 'http://assistant.test/api/v1',
        httpClient: MockClient((request) async {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'mode': 'chat',
              'message': '文字仍然保留。',
              'audio': <String, dynamic>{'base64': 'not-valid-base64'},
            }),
            200,
            headers: const <String, String>{'content-type': 'application/json'},
          );
        }),
      ),
    );

    final reply = await api.chat(message: '測試');

    expect(reply.message, '文字仍然保留。');
    expect(reply.audio, isNull);
  });
}
