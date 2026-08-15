import 'package:desk_companion/ai/assistant_decision_client.dart';
import 'package:desk_companion/ai/assistant_interaction_controller.dart';
import 'package:desk_companion/ai/assistant_reply.dart';
import 'package:desk_companion/voice/voice_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'handles clear local action without contacting assistant backend',
    () async {
      final decisionClient = _UnexpectedDecisionClient();
      final controller = AssistantInteractionController(
        decisionClient: decisionClient,
      );

      final result = await controller.handleText(text: '幫我開一個 25 分鐘番茄鐘');

      expect(result.usedFallback, isFalse);
      expect(result.command?.type, VoiceCommandType.startPomodoro);
      expect(result.command?.durationMinutes, 25);
      expect(result.shouldRunAction, isTrue);
      expect(decisionClient.decideCallCount, 0);
      expect(decisionClient.chatCallCount, 0);
    },
  );

  test('keeps every supported app command on device', () async {
    final decisionClient = _UnexpectedDecisionClient();
    final controller = AssistantInteractionController(
      decisionClient: decisionClient,
    );
    final cases = <String, VoiceCommandType>{
      '暫停番茄鐘': VoiceCommandType.pausePomodoro,
      '繼續番茄鐘': VoiceCommandType.resumePomodoro,
      '停止番茄鐘': VoiceCommandType.stopPomodoro,
      '番茄鐘還剩多久': VoiceCommandType.requestTimerStatus,
      '幫我看今天的專注摘要': VoiceCommandType.requestFocusSummary,
      '我有點累': VoiceCommandType.reportTired,
      '我剛剛分心': VoiceCommandType.reportDistracted,
      '我想休息': VoiceCommandType.requestBreak,
    };

    for (final entry in cases.entries) {
      final result = await controller.handleText(text: entry.key);
      expect(result.command?.type, entry.value, reason: entry.key);
      expect(result.shouldRunAction, isTrue, reason: entry.key);
      expect(result.usedFallback, isFalse, reason: entry.key);
    }

    expect(decisionClient.decideCallCount, 0);
    expect(decisionClient.chatCallCount, 0);
  });

  test('uses chat instead of local unknown for normal conversation', () async {
    final decisionClient = _DecideFailsChatSucceedsClient();
    final controller = AssistantInteractionController(
      decisionClient: decisionClient,
      timeout: const Duration(seconds: 1),
    );

    final result = await controller.handleText(text: '今天心情有點複雜');

    expect(result.usedFallback, isFalse);
    expect(result.command, isNull);
    expect(result.response.actionLabel, 'assistant_chat');
    expect(result.response.message, '我在，慢慢說。');
    expect(decisionClient.decideCallCount, 0);
    expect(decisionClient.chatCallCount, 1);
  });

  test('answers common greetings locally without contacting backend', () async {
    final decisionClient = _UnexpectedDecisionClient();
    final controller = AssistantInteractionController(
      decisionClient: decisionClient,
    );

    final result = await controller.handleText(text: '早安');

    expect(result.response.message, '早安，今天也一起加油吧！');
    expect(result.reply.model, 'local-social');
    expect(result.usedFallback, isFalse);
    expect(decisionClient.decideCallCount, 0);
    expect(decisionClient.chatCallCount, 0);
  });
}

class _UnexpectedDecisionClient implements AssistantDecisionClient {
  int decideCallCount = 0;
  int chatCallCount = 0;

  @override
  Future<AssistantReply> decide({
    required String message,
    List<AssistantConversationMessage> history = const [],
    Map<String, dynamic>? context,
    String? accessToken,
  }) {
    decideCallCount += 1;
    return Future<AssistantReply>.error(
      StateError('Local commands must not call decide().'),
    );
  }

  @override
  Future<AssistantReply> chat({
    required String message,
    List<AssistantConversationMessage> history = const [],
    Map<String, dynamic>? context,
    String? accessToken,
  }) {
    chatCallCount += 1;
    return Future<AssistantReply>.error(
      StateError('Local commands must not call chat().'),
    );
  }
}

class _DecideFailsChatSucceedsClient implements AssistantDecisionClient {
  int decideCallCount = 0;
  int chatCallCount = 0;

  @override
  Future<AssistantReply> decide({
    required String message,
    List<AssistantConversationMessage> history = const [],
    Map<String, dynamic>? context,
    String? accessToken,
  }) {
    decideCallCount += 1;
    return Future<AssistantReply>.error(Exception('decide unavailable'));
  }

  @override
  Future<AssistantReply> chat({
    required String message,
    List<AssistantConversationMessage> history = const [],
    Map<String, dynamic>? context,
    String? accessToken,
  }) async {
    chatCallCount += 1;
    return const AssistantReply(
      mode: AssistantMode.chat,
      message: '我在，慢慢說。',
      chatReply: '我在，慢慢說。',
    );
  }
}
