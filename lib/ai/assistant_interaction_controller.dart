import 'dart:async';

import '../companion/companion_response.dart';
import '../companion/companion_response_builder.dart';
import '../voice/voice_command.dart';
import '../voice/voice_command_parser.dart';
import '../voice/voice_result.dart';
import 'assistant_decision_client.dart';
import 'assistant_intent_mapper.dart';
import 'assistant_reply.dart';
import 'pending_action_controller.dart';

class AssistantInteractionResult {
  const AssistantInteractionResult({
    required this.reply,
    required this.response,
    this.command,
    this.pendingAction,
    this.usedFallback = false,
  });

  final AssistantReply reply;
  final CompanionResponse response;
  final VoiceCommand? command;
  final PendingAction? pendingAction;
  final bool usedFallback;

  bool get shouldRunAction => command != null && pendingAction == null;
}

class AssistantInteractionController {
  const AssistantInteractionController({
    required AssistantDecisionClient decisionClient,
    this.intentMapper = const AssistantIntentMapper(),
    this.voiceParser = const VoiceCommandParser(),
    this.responseBuilder = const CompanionResponseBuilder(),
    this.timeout = const Duration(seconds: 20),
  }) : _decisionClient = decisionClient;

  final AssistantDecisionClient _decisionClient;
  final AssistantIntentMapper intentMapper;
  final VoiceCommandParser voiceParser;
  final CompanionResponseBuilder responseBuilder;
  final Duration timeout;

  Future<AssistantInteractionResult> handleText({
    required String text,
    List<AssistantConversationMessage> history = const [],
    Map<String, dynamic>? context,
    String? accessToken,
  }) async {
    final localCommand = _parseLocalCommand(text);
    if (_shouldUseLocalFallbackCommand(localCommand, text)) {
      return _localActionResult(localCommand, usedFallback: false);
    }

    if (_isAmbiguousStopSignal(text)) {
      return _clarifyStopSignalResult();
    }

    final localChatReply = _localSocialReply(text);
    if (localChatReply != null) {
      return _localChatResult(localChatReply);
    }

    if (!_shouldAskBackendToDecide(localCommand, text)) {
      try {
        final reply = await _decisionClient
            .chat(
              message: text,
              history: history,
              context: context,
              accessToken: accessToken,
            )
            .timeout(timeout);
        return _fromAssistantReply(reply, text);
      } catch (error) {
        return _assistantUnavailableResult(error);
      }
    }

    try {
      final reply = await _decisionClient
          .decide(
            message: text,
            history: history,
            context: context,
            accessToken: accessToken,
          )
          .timeout(timeout);
      return _fromAssistantReply(reply, text);
    } catch (error) {
      return _recoverFromDecideFailure(
        text: text,
        history: history,
        context: context,
        accessToken: accessToken,
        error: error,
      );
    }
  }

  AssistantInteractionResult _fromAssistantReply(
    AssistantReply reply,
    String sourceText,
  ) {
    switch (reply.mode) {
      case AssistantMode.action:
        final command = intentMapper.toVoiceCommand(
          intent: reply.intent ?? reply.action,
          sourceText: sourceText,
          confidence: reply.confidence,
          parameters: reply.parameters,
        );
        if (command == null) {
          return _clarifyResult(reply);
        }

        final response = responseBuilder.fromVoiceCommand(command);
        if (reply.needsConfirmation) {
          final pendingAction = PendingAction(
            command: command,
            confirmationText: reply.confirmationText ?? response.message,
          );
          return AssistantInteractionResult(
            reply: reply,
            response: CompanionResponse(
              source: CompanionResponseSource.voice,
              tone: CompanionResponseTone.supportive,
              message: pendingAction.confirmationText,
              actionLabel: 'assistant_confirm_action',
              shouldNotify: true,
            ),
            command: command,
            pendingAction: pendingAction,
          );
        }

        return AssistantInteractionResult(
          reply: reply,
          response: response,
          command: command,
        );
      case AssistantMode.clarify:
        return _clarifyResult(reply);
      case AssistantMode.chat:
        return AssistantInteractionResult(
          reply: reply,
          response: CompanionResponse(
            source: CompanionResponseSource.voice,
            tone: CompanionResponseTone.supportive,
            message: reply.chatReply ?? reply.message,
            actionLabel: 'assistant_chat',
          ),
        );
    }
  }

  AssistantInteractionResult _clarifyResult(AssistantReply reply) {
    return AssistantInteractionResult(
      reply: reply,
      response: CompanionResponse(
        source: CompanionResponseSource.voice,
        tone: CompanionResponseTone.supportive,
        message: reply.confirmationText ?? reply.message,
        actionLabel: 'assistant_clarify',
        shouldNotify: true,
      ),
    );
  }

  Future<AssistantInteractionResult> _recoverFromDecideFailure({
    required String text,
    required List<AssistantConversationMessage> history,
    required Map<String, dynamic>? context,
    required String? accessToken,
    required Object error,
  }) async {
    final localCommand = _parseLocalCommand(text);
    if (_shouldUseLocalFallbackCommand(localCommand, text)) {
      return _localActionResult(localCommand, usedFallback: true);
    }

    try {
      final chatReply = await _decisionClient
          .chat(
            message: text,
            history: history,
            context: context,
            accessToken: accessToken,
          )
          .timeout(timeout);
      return _fromAssistantReply(chatReply, text);
    } catch (_) {
      return _assistantUnavailableResult(error);
    }
  }

  AssistantInteractionResult _assistantUnavailableResult(Object error) {
    return AssistantInteractionResult(
      reply: AssistantReply(
        mode: AssistantMode.chat,
        message: 'Assistant unavailable: $error',
      ),
      response: const CompanionResponse(
        source: CompanionResponseSource.voice,
        tone: CompanionResponseTone.supportive,
        message: 'AI 服務暫時連不上；番茄鐘仍可直接說「開始、暫停、繼續、停止」。',
        actionLabel: 'assistant_unavailable',
        shouldNotify: true,
      ),
      usedFallback: true,
    );
  }

  AssistantInteractionResult _localActionResult(
    VoiceCommand command, {
    required bool usedFallback,
  }) {
    return AssistantInteractionResult(
      reply: AssistantReply(
        mode: AssistantMode.action,
        message: usedFallback
            ? 'Assistant unavailable; used local command parser.'
            : 'Handled by local command parser.',
        intent: command.type.name,
        parameters: command.durationMinutes == null
            ? const <String, dynamic>{}
            : <String, dynamic>{'durationMinutes': command.durationMinutes},
      ),
      response: responseBuilder.fromVoiceCommand(command),
      command: command,
      usedFallback: usedFallback,
    );
  }

  AssistantInteractionResult _localChatResult(String message) {
    return AssistantInteractionResult(
      reply: AssistantReply(
        mode: AssistantMode.chat,
        message: message,
        chatReply: message,
        model: 'local-social',
      ),
      response: CompanionResponse(
        source: CompanionResponseSource.voice,
        tone: CompanionResponseTone.supportive,
        message: message,
        actionLabel: 'assistant_chat',
      ),
    );
  }

  bool _isAmbiguousStopSignal(String text) {
    final normalized = text
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[\uFF0C\u3002\uFF01\uFF1F,.!?]'), '');
    return _ambiguousStopSignals.contains(normalized);
  }

  AssistantInteractionResult _clarifyStopSignalResult() {
    const message =
        '\u4f60\u662f\u60f3\u66ab\u505c\u756a\u8304\u9418\uff0c\u9084\u662f\u8981\u76f4\u63a5\u505c\u6b62\u5462\uff1f';
    return AssistantInteractionResult(
      reply: const AssistantReply(
        mode: AssistantMode.clarify,
        message: message,
        chatReply: message,
        model: 'local-clarify',
      ),
      response: const CompanionResponse(
        source: CompanionResponseSource.voice,
        tone: CompanionResponseTone.supportive,
        message: message,
        actionLabel: 'assistant_clarify_stop_signal',
        shouldNotify: true,
      ),
    );
  }

  String? _localSocialReply(String text) {
    final normalized = text
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[，。！？,.!?]'), '');
    if (normalized.length > 12) return null;

    if (_containsAny(normalized, const ['早安', '早上好'])) {
      return '早安，今天也一起加油吧！';
    }
    if (normalized.contains('午安')) {
      return '午安，記得讓自己喘口氣。';
    }
    if (normalized.contains('晚安')) {
      return '晚安，今天辛苦了。';
    }
    if (_containsAny(normalized, const ['你好', '嗨', '哈囉', 'hello'])) {
      return '你好，我在這裡。';
    }
    if (_containsAny(normalized, const ['謝謝', '感謝'])) {
      return '不客氣，我一直都在。';
    }
    if (_containsAny(normalized, const ['掰掰', '再見'])) {
      return '再見，等等再來找我吧。';
    }
    return null;
  }

  VoiceCommand _parseLocalCommand(String text) {
    final result = VoiceRecognitionResult(
      sessionId: 'assistant-fallback',
      eventType: VoiceEventType.finalResult,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      transcript: text,
      formattedTranscript: text,
      isFinal: true,
      candidates: [VoiceCandidate(text: text, confidence: 1)],
    );
    return voiceParser.parse(result);
  }

  bool _shouldUseLocalFallbackCommand(VoiceCommand command, String text) {
    if (!command.isActionable) return false;

    final normalized = text
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[\uFF0C\u3002\uFF01\uFF1F,.!?]'), '');

    switch (command.type) {
      case VoiceCommandType.requestFocusSummary:
        return _containsAny(normalized, const [
          '摘要',
          '統計',
          '專注狀態',
          '做幾輪',
          '幾輪',
          '有沒有分心',
        ]);
      case VoiceCommandType.startPomodoro:
        return _containsAny(normalized, const ['番茄鐘', '專注鐘', '專注時間']) ||
            (_containsAny(normalized, const ['開始', '設定', '設置', '幫我']) &&
                _containsAny(normalized, const ['專注', '分心']));
      case VoiceCommandType.pausePomodoro:
      case VoiceCommandType.stopPomodoro:
        return !_hasNegatedStateChange(normalized);
      case VoiceCommandType.resumePomodoro:
      case VoiceCommandType.requestTimerStatus:
      case VoiceCommandType.reportTired:
      case VoiceCommandType.reportDistracted:
      case VoiceCommandType.requestBreak:
      case VoiceCommandType.confirmStartPomodoro:
        return true;
      case VoiceCommandType.unknown:
      case VoiceCommandType.ignored:
        return false;
    }
  }

  bool _shouldAskBackendToDecide(VoiceCommand command, String text) {
    final normalized = text
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[，。！？,.!?]'), '');
    if (_containsAny(normalized, _backendDecisionSignals)) return true;
    return _containsAny(normalized, const [
      '番茄鐘',
      '專注鐘',
      '計時器',
      '開始',
      '暫停',
      '繼續',
      '停止',
      '剩多久',
      '摘要',
      '統計',
    ]);
  }

  bool _hasNegatedStateChange(String normalized) {
    return _containsAny(normalized, const [
      '\u4e0d\u8981\u505c\u6b62',
      '\u4e0d\u60f3\u505c\u6b62',
      '\u5148\u4e0d\u505c\u6b62',
      '\u5148\u4e0d\u8981\u505c\u6b62',
      '\u4e0d\u662f\u505c\u6b62',
      '\u4e0d\u8981\u66ab\u505c',
      '\u4e0d\u60f3\u66ab\u505c',
      '\u5148\u4e0d\u66ab\u505c',
      '\u5148\u4e0d\u8981\u66ab\u505c',
      '\u4e0d\u662f\u66ab\u505c',
    ]);
  }

  bool _containsAny(String text, List<String> keywords) {
    return keywords.any(text.contains);
  }
}

const List<String> _ambiguousStopSignals = ['\u505c'];

const List<String> _backendDecisionSignals = [
  '\u756a\u8304\u9418',
  '\u756a\u8304\u4e2d',
  '\u5c08\u6ce8\u9418',
  '\u5c08\u6ce8\u6642\u9593',
  '\u8a08\u6642',
  '\u8a08\u6642\u5668',
  '\u958b\u59cb',
  '\u958b',
  '\u8a2d\u5b9a',
  '\u8a2d\u7f6e',
  '\u66ab\u505c',
  '\u505c\u4e00\u4e0b',
  '\u558a\u505c',
  '\u505c\u6b62',
  '\u4e2d\u6b62',
  '\u95dc\u6389',
  '\u53d6\u6d88',
  '\u7e7c\u7e8c',
  '\u6062\u5fa9',
  '\u5269\u591a\u4e45',
  '\u9084\u5269',
  '\u5269\u5e7e\u5206',
];
