import '../ai/assistant_reply.dart';
import '../ai/assistant_decision_client.dart';
import 'api_client.dart';

class AssistantApi implements AssistantDecisionClient {
  const AssistantApi(this._client);

  final ApiClient _client;

  @override
  Future<AssistantReply> chat({
    required String message,
    List<AssistantConversationMessage> history = const [],
    Map<String, dynamic>? context,
    String? accessToken,
  }) async {
    final data = await _client.post(
      '/assistant/chat',
      body: <String, dynamic>{
        'message': message,
        if (history.isNotEmpty)
          'history': history.map((item) => item.toJson()).toList(),
        if (context != null && context.isNotEmpty) 'context': context,
      },
      accessToken: accessToken,
    );
    return AssistantReply.fromJson(data);
  }

  @override
  Future<AssistantReply> decide({
    required String message,
    List<AssistantConversationMessage> history = const [],
    Map<String, dynamic>? context,
    String? accessToken,
  }) async {
    final data = await _client.post(
      '/assistant/decide',
      body: <String, dynamic>{
        'message': message,
        if (history.isNotEmpty)
          'history': history.map((item) => item.toJson()).toList(),
        if (context != null && context.isNotEmpty) 'context': context,
      },
      accessToken: accessToken,
    );
    return AssistantReply.fromJson(data);
  }
}
