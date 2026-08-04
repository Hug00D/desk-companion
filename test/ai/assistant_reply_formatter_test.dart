import 'package:flutter_test/flutter_test.dart';

import 'package:desk_companion/ai/assistant_reply_formatter.dart';

void main() {
  test('keeps only one sentence for a greeting', () {
    final result = AssistantReplyFormatter.concise(
      sourceText: '早安',
      reply: '早上好！希望你今天精神飽滿。目前還沒有開始番茄鐘，需要時可以告訴我。祝你今天充滿活力！',
    );

    expect(result, '早上好！');
  });

  test('keeps at most two sentences for normal conversation', () {
    final result = AssistantReplyFormatter.concise(
      sourceText: '我今天讀書有點累',
      reply: '聽起來你已經努力一段時間了。先休息幾分鐘再繼續吧。喝水也很重要。',
    );

    expect(result, '聽起來你已經努力一段時間了。先休息幾分鐘再繼續吧。');
  });

  test('limits an unpunctuated response to sixty characters', () {
    final result = AssistantReplyFormatter.concise(
      sourceText: '幫我鼓勵一下',
      reply: List<String>.filled(80, '加').join(),
    );

    expect(result.length, 61);
    expect(result.endsWith('…'), isTrue);
  });

  test('removes an English opening from a Chinese conversation', () {
    final result = AssistantReplyFormatter.concise(
      sourceText: '我今天有去健身',
      reply: 'Sounds good!運動對身體很好呢！',
    );

    expect(result, '聽起來不錯！運動對身體很好呢！');
    expect(RegExp(r'[A-Za-z]').hasMatch(result), isFalse);
  });

  test('uses a Chinese fallback when a Chinese reply is entirely English', () {
    final result = AssistantReplyFormatter.concise(
      sourceText: '我今天有去健身',
      reply: 'Sounds good!',
    );

    expect(RegExp(r'[\u3400-\u9fff]').hasMatch(result), isTrue);
    expect(RegExp(r'[A-Za-z]').hasMatch(result), isFalse);
  });

  test('removes model separator artifacts before speech synthesis', () {
    final result = AssistantReplyFormatter.concise(
      sourceText: '好',
      reply: '好 ==========================================================…',
    );

    expect(result, '好。');
    expect(result, isNot(contains('=')));
  });

  test('removes hidden model reasoning and keeps the visible reply', () {
    final result = AssistantReplyFormatter.concise(
      sourceText: '我今天很無聊',
      reply: '<think>分析使用者情緒</think>那我陪你聊點輕鬆的。',
    );

    expect(result, '那我陪你聊點輕鬆的。');
  });

  test('uses a safe fallback when a reply only contains artifacts', () {
    final result = AssistantReplyFormatter.concise(
      sourceText: '你在嗎',
      reply: '================================',
    );

    expect(result, '我剛剛的回覆出了點問題，請再說一次。');
  });
}
