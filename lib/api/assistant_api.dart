import '../ai/assistant_reply.dart';
import '../ai/assistant_decision_client.dart';
import 'api_client.dart';

class AssistantApi implements AssistantDecisionClient {
  const AssistantApi(this._client);

  final ApiClient _client;

  static const String _chatStyleInstruction = '''

[回覆風格]
只能使用繁體中文，自然地回應使用者當下的情緒或話題，最多兩個短句。
禁止使用英文字母、英文單字、英文開場、羅馬拼音或中英夾雜；外語概念請改用繁體中文表達。
送出回覆前請自行檢查，確保整段內容沒有任何英文。
除非使用者主動詢問專注、讀書、工作效率或番茄鐘，否則不要提到番茄鐘、效率、專注工具或健康管理。
不要每次都給建議；日常聊天可以單純陪伴、接話或幽默回應。
''';

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
        'message': '$message$_chatStyleInstruction',
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
