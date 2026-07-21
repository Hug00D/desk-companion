import 'assistant_reply.dart';

abstract class AssistantDecisionClient {
  Future<AssistantReply> decide({
    required String message,
    List<AssistantConversationMessage> history,
    Map<String, dynamic>? context,
    String? accessToken,
  });

  Future<AssistantReply> chat({
    required String message,
    List<AssistantConversationMessage> history,
    Map<String, dynamic>? context,
    String? accessToken,
  });
}
