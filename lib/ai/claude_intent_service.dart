import 'dart:convert';

import 'package:http/http.dart' as http;

import 'companion_ai_decision.dart';

class ClaudeIntentContext {
  const ClaudeIntentContext({
    required this.pomodoroStatus,
    required this.pomodoroRemaining,
    required this.companionStatus,
    required this.visionEvent,
    required this.hasFace,
    required this.focusSummary,
  });

  final String pomodoroStatus;
  final String pomodoroRemaining;
  final String companionStatus;
  final String visionEvent;
  final bool hasFace;
  final String focusSummary;
}

class ClaudeIntentService {
  ClaudeIntentService({
    http.Client? httpClient,
    this.apiKey = const String.fromEnvironment('ANTHROPIC_API_KEY'),
    this.model = const String.fromEnvironment(
      'ANTHROPIC_MODEL',
      defaultValue: 'claude-haiku-4-5',
    ),
    this.endpoint = const String.fromEnvironment(
      'ANTHROPIC_MESSAGES_ENDPOINT',
      defaultValue: 'https://api.anthropic.com/v1/messages',
    ),
  }) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  final String apiKey;
  final String model;
  final String endpoint;

  bool get isEnabled => apiKey.trim().isNotEmpty;

  Future<CompanionAiDecision?> decide({
    required String userText,
    required ClaudeIntentContext context,
  }) async {
    if (!isEnabled) return null;

    final response = await _httpClient.post(
      Uri.parse(endpoint),
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode({
        'model': model,
        'max_tokens': 700,
        'system': _systemPrompt,
        'messages': [
          {
            'role': 'user',
            'content': _buildUserPrompt(userText: userText, context: context),
          },
        ],
        'output_config': {
          'format': {
            'type': 'json_schema',
            'name': 'desk_companion_intent_decision',
            'schema': _decisionSchema,
          },
        },
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ClaudeIntentException(
        'Claude API failed (${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final text = _extractText(decoded);
    if (text == null || text.trim().isEmpty) {
      throw const ClaudeIntentException(
        'Claude response did not contain text.',
      );
    }

    final decisionJson = jsonDecode(text) as Map<String, dynamic>;
    return CompanionAiDecision.fromJson(decisionJson);
  }

  String _buildUserPrompt({
    required String userText,
    required ClaudeIntentContext context,
  }) {
    return '''
使用者剛剛說：
$userText

目前 App 狀態：
- 番茄鐘狀態：${context.pomodoroStatus}
- 番茄鐘剩餘：${context.pomodoroRemaining}
- 視覺狀態：${context.companionStatus}
- 視覺事件：${context.visionEvent}
- 畫面是否有人臉：${context.hasFace}
- 今日摘要：${context.focusSummary}

請判斷使用者是要執行功能、詢問狀態、回報感受、還是單純聊天。
''';
  }

  String? _extractText(Map<String, dynamic> response) {
    final content = response['content'];
    if (content is! List) return null;

    for (final block in content) {
      if (block is Map && block['type'] == 'text') {
        return block['text']?.toString();
      }
    }

    return null;
  }
}

class ClaudeIntentException implements Exception {
  const ClaudeIntentException(this.message);

  final String message;

  @override
  String toString() => message;
}

const String _systemPrompt = '''
你是 Desk Companion 裡的語音理解與回應決策層。
你的任務不是直接執行功能，而是判斷使用者意圖，回傳 App 可以安全處理的 JSON。

你只能使用這些 intent：
- none：純聊天或沒有功能需求
- start_pomodoro：開始番茄鐘或專注計時
- pause_pomodoro：暫停番茄鐘
- resume_pomodoro：繼續番茄鐘
- stop_pomodoro：停止番茄鐘
- request_break：使用者想休息
- request_focus_summary：詢問今日專注摘要、統計、做了幾輪
- request_timer_status：詢問番茄鐘剩餘時間或目前狀態
- report_tired：使用者說自己累、眼睛酸、想睡
- report_distracted：使用者說自己分心、無法專心

安全規則：
- 會改變狀態的功能必須 needsConfirmation=true：start_pomodoro、pause_pomodoro、resume_pomodoro、stop_pomodoro、request_break。
- 查詢狀態與摘要通常不需要確認。
- 如果語意不清楚，mode 用 clarify，intent 用 none，chatReply 寫一句自然追問。
- 如果使用者只是聊天，mode 用 chat，intent 用 none，給出溫和、簡短、有陪伴感的中文回應。
- chatReply 和 confirmationText 都不要超過 40 個中文字。
- 不要聲稱你已經執行功能，只能說「要不要我幫你...」。
''';

const Map<String, dynamic> _decisionSchema = {
  'type': 'object',
  'additionalProperties': false,
  'required': [
    'mode',
    'intent',
    'confidence',
    'needsConfirmation',
    'confirmationText',
    'chatReply',
    'parameters',
  ],
  'properties': {
    'mode': {
      'type': 'string',
      'enum': ['action', 'chat', 'clarify'],
    },
    'intent': {
      'type': 'string',
      'enum': [
        'none',
        'start_pomodoro',
        'pause_pomodoro',
        'resume_pomodoro',
        'stop_pomodoro',
        'request_break',
        'request_focus_summary',
        'request_timer_status',
        'report_tired',
        'report_distracted',
      ],
    },
    'confidence': {'type': 'number'},
    'needsConfirmation': {'type': 'boolean'},
    'confirmationText': {'type': 'string'},
    'chatReply': {'type': 'string'},
    'parameters': {
      'type': 'object',
      'additionalProperties': false,
      'required': ['durationMinutes'],
      'properties': {
        'durationMinutes': {
          'type': 'integer',
          'description': '番茄鐘分鐘數。沒有指定時填 0。',
        },
      },
    },
  },
};
