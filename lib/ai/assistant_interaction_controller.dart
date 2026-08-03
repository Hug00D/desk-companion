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
      return AssistantInteractionResult(
        reply: AssistantReply(
          mode: AssistantMode.chat,
          message: 'Assistant unavailable after decide failure: $error',
        ),
        response: const CompanionResponse(
          source: CompanionResponseSource.voice,
          tone: CompanionResponseTone.supportive,
          message: 'AI 服務暫時連不上；如果你要操作番茄鐘，可以直接說「開始、暫停、繼續、停止」。',
          actionLabel: 'assistant_unavailable',
          shouldNotify: true,
        ),
        usedFallback: true,
      );
    }
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
      case VoiceCommandType.resumePomodoro:
      case VoiceCommandType.stopPomodoro:
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

  bool _containsAny(String text, List<String> keywords) {
    return keywords.any(text.contains);
  }
}
