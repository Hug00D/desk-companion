import 'dart:typed_data';

import 'package:desk_companion/ai/assistant_reply.dart';
import 'package:desk_companion/voice/assistant_voice_reply_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = AssistantVoiceReplyPolicy();
  final audio = AssistantAudio(
    requestId: 'reply-1',
    contentType: 'audio/wav',
    bytes: Uint8List.fromList(<int>[1, 2, 3]),
  );

  test('enabled chat reply with audio is played', () {
    expect(
      policy.shouldPlay(
        voiceReplyEnabled: true,
        dynamicVoiceEnabled: true,
        mode: AssistantMode.chat,
        usedFallback: false,
        audio: audio,
      ),
      isTrue,
    );
  });

  test('disabled voice reply always keeps the answer text-only', () {
    expect(
      policy.shouldPlay(
        voiceReplyEnabled: false,
        dynamicVoiceEnabled: true,
        mode: AssistantMode.chat,
        usedFallback: false,
        audio: audio,
      ),
      isFalse,
    );
  });

  test(
    'non-chat, fallback, disabled engine, or missing audio stays silent',
    () {
      expect(
        policy.shouldPlay(
          voiceReplyEnabled: true,
          dynamicVoiceEnabled: true,
          mode: AssistantMode.action,
          usedFallback: false,
          audio: audio,
        ),
        isFalse,
      );
      expect(
        policy.shouldPlay(
          voiceReplyEnabled: true,
          dynamicVoiceEnabled: true,
          mode: AssistantMode.chat,
          usedFallback: true,
          audio: audio,
        ),
        isFalse,
      );
      expect(
        policy.shouldPlay(
          voiceReplyEnabled: true,
          dynamicVoiceEnabled: false,
          mode: AssistantMode.chat,
          usedFallback: false,
          audio: audio,
        ),
        isFalse,
      );
      expect(
        policy.shouldPlay(
          voiceReplyEnabled: true,
          dynamicVoiceEnabled: true,
          mode: AssistantMode.chat,
          usedFallback: false,
          audio: null,
        ),
        isFalse,
      );
    },
  );
}
