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
請使用繁體中文，語氣溫和、簡短、有陪伴感。
回覆通常 1 到 2 句即可，不要說教，也不要輸出 JSON。
如果使用者只是聊天，先自然回應，再給一個小而可行的建議。
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
