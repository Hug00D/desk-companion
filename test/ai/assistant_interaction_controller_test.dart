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

  test('clarifies single ambiguous stop signal without backend calls', () async {
    final decisionClient = _UnexpectedDecisionClient();
    final controller = AssistantInteractionController(
      decisionClient: decisionClient,
    );

    for (final text in const ['\u505c', '\u505c\u3002', ' \u505c ']) {
      final result = await controller.handleText(text: text);

      expect(result.reply.mode, AssistantMode.clarify, reason: text);
      expect(result.reply.model, 'local-clarify', reason: text);
      expect(
        result.response.message,
        '\u4f60\u662f\u60f3\u66ab\u505c\u756a\u8304\u9418\uff0c\u9084\u662f\u8981\u76f4\u63a5\u505c\u6b62\u5462\uff1f',
        reason: text,
      );
      expect(
        result.response.actionLabel,
        'assistant_clarify_stop_signal',
        reason: text,
      );
      expect(result.command, isNull, reason: text);
      expect(result.pendingAction, isNull, reason: text);
      expect(result.shouldRunAction, isFalse, reason: text);
    }

    expect(decisionClient.decideCallCount, 0);
    expect(decisionClient.chatCallCount, 0);
  });

  test('sends action-like unknown text to decide instead of chat', () async {
    final decisionClient = _DecideSucceedsClient(
      const AssistantReply(
        mode: AssistantMode.action,
        message: 'ok',
        intent: 'start_pomodoro',
        confidence: 0.9,
      ),
    );
    final controller = AssistantInteractionController(
      decisionClient: decisionClient,
    );

    final result = await controller.handleText(
      text: '\u958b\u59cb\u8a08\u6642',
    );

    expect(result.command?.type, VoiceCommandType.startPomodoro);
    expect(decisionClient.decideCallCount, 1);
    expect(decisionClient.chatCallCount, 0);
  });

  test('negated stop text is not executed by local fallback', () async {
    final decisionClient = _DecideFailsChatSucceedsClient();
    final controller = AssistantInteractionController(
      decisionClient: decisionClient,
      timeout: const Duration(seconds: 1),
    );

    final result = await controller.handleText(
      text: '\u5148\u4e0d\u8981\u505c\u6b62',
    );

    expect(result.command, isNull);
    expect(result.shouldRunAction, isFalse);
    expect(decisionClient.decideCallCount, 1);
    expect(decisionClient.chatCallCount, 1);
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

class _DecideSucceedsClient implements AssistantDecisionClient {
  _DecideSucceedsClient(this.reply);

  final AssistantReply reply;
  int decideCallCount = 0;
  int chatCallCount = 0;

  @override
  Future<AssistantReply> decide({
    required String message,
    List<AssistantConversationMessage> history = const [],
    Map<String, dynamic>? context,
    String? accessToken,
  }) async {
    decideCallCount += 1;
    return reply;
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
      StateError('Action-like text must call decide().'),
    );
  }
}
