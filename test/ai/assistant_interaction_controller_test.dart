import 'package:desk_companion/ai/assistant_decision_client.dart';
import 'package:desk_companion/ai/assistant_interaction_controller.dart';
import 'package:desk_companion/ai/assistant_reply.dart';
import 'package:desk_companion/voice/voice_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'falls back to local voice parser for clear action when decide times out',
    () async {
      final controller = AssistantInteractionController(
        decisionClient: _TimeoutDecisionClient(),
        timeout: const Duration(milliseconds: 1),
      );

      final result = await controller.handleText(text: '幫我開一個 25 分鐘番茄鐘');

      expect(result.usedFallback, isTrue);
      expect(result.command?.type, VoiceCommandType.startPomodoro);
      expect(result.command?.durationMinutes, 25);
      expect(result.shouldRunAction, isTrue);
    },
  );

  test('uses chat instead of local unknown for normal conversation', () async {
    final controller = AssistantInteractionController(
      decisionClient: _DecideFailsChatSucceedsClient(),
      timeout: const Duration(seconds: 1),
    );

    final result = await controller.handleText(text: '今天心情有點複雜');

    expect(result.usedFallback, isFalse);
    expect(result.command, isNull);
    expect(result.response.actionLabel, 'assistant_chat');
    expect(result.response.message, '我在，慢慢說。');
  });
}

class _TimeoutDecisionClient implements AssistantDecisionClient {
  @override
  Future<AssistantReply> decide({
    required String message,
    List<AssistantConversationMessage> history = const [],
    Map<String, dynamic>? context,
    String? accessToken,
  }) {
    return Future<AssistantReply>.delayed(
      const Duration(seconds: 1),
      () => const AssistantReply(
        mode: AssistantMode.chat,
        message: 'late response',
      ),
    );
  }

  @override
  Future<AssistantReply> chat({
    required String message,
    List<AssistantConversationMessage> history = const [],
    Map<String, dynamic>? context,
    String? accessToken,
  }) {
    return Future<AssistantReply>.delayed(
      const Duration(seconds: 1),
      () => const AssistantReply(
        mode: AssistantMode.chat,
        message: 'late chat response',
      ),
    );
  }
}

class _DecideFailsChatSucceedsClient implements AssistantDecisionClient {
  @override
  Future<AssistantReply> decide({
    required String message,
    List<AssistantConversationMessage> history = const [],
    Map<String, dynamic>? context,
    String? accessToken,
  }) {
    return Future<AssistantReply>.error(Exception('decide unavailable'));
  }

  @override
  Future<AssistantReply> chat({
    required String message,
    List<AssistantConversationMessage> history = const [],
    Map<String, dynamic>? context,
    String? accessToken,
  }) async {
    return const AssistantReply(
      mode: AssistantMode.chat,
      message: '我在，慢慢說。',
      chatReply: '我在，慢慢說。',
    );
  }
}
