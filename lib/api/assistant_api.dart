import '../ai/assistant_decision_client.dart';
import '../ai/assistant_reply.dart';
import 'api_client.dart';

class AssistantApi implements AssistantDecisionClient {
  const AssistantApi(this._client, {this.chatStyleInstructionProvider});

  final ApiClient _client;
  final String Function()? chatStyleInstructionProvider;

  static const Duration _combinedReplyTimeout = Duration(seconds: 180);

  static const String _defaultChatStyleInstruction = '''

[AI 回覆語氣設定]
只能使用繁體中文，語氣溫和、簡短、有陪伴感，回覆通常 1 到 2 句即可。
禁止使用英文字母、英文單字、英文開場、羅馬拼音或中英夾雜；外語概念請改用繁體中文表達。
送出回覆前請自行檢查，確保整段內容沒有任何英文，也不要輸出 JSON。
除非使用者主動詢問專注、讀書、工作效率或番茄鐘，否則不要提到番茄鐘、效率、專注工具或健康管理。
如果使用者只是聊天，先自然回應；不必每次都給建議，也可以單純陪伴、接話或幽默回應。
如果使用者要求操作番茄鐘或查詢狀態，優先清楚確認結果。
''';

  String get _resolvedChatStyleInstruction {
    return chatStyleInstructionProvider?.call() ?? _defaultChatStyleInstruction;
  }

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
        'message': '$message$_resolvedChatStyleInstruction',
        if (history.isNotEmpty)
          'history': history.map((item) => item.toJson()).toList(),
        if (context != null && context.isNotEmpty) 'context': context,
      },
      accessToken: accessToken,
      timeout: _combinedReplyTimeout,
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
      timeout: _combinedReplyTimeout,
    );
    return AssistantReply.fromJson(data);
  }
}
