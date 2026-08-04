class AssistantReplyFormatter {
  const AssistantReplyFormatter._();

  static String concise({required String sourceText, required String reply}) {
    final artifactFreeReply = _removeModelArtifacts(reply);
    final normalized = _enforceChineseForChineseInput(
      sourceText: sourceText,
      reply: artifactFreeReply,
    ).replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) {
      return '我剛剛的回覆出了點問題，請再說一次。';
    }

    final briefExchange = _isBriefExchange(sourceText);
    final sentenceLimit = briefExchange ? 1 : 2;
    final characterLimit = briefExchange ? 32 : 60;
    final sentences = RegExp(
      r'[^。！？!?]+[。！？!?]?',
    ).allMatches(normalized).map((match) => match.group(0)!.trim());
    final selected = sentences
        .where((sentence) => sentence.isNotEmpty)
        .take(sentenceLimit)
        .join();
    final candidate = selected.isEmpty ? normalized : selected;

    if (candidate.length <= characterLimit) {
      return _ensureSentenceEnding(candidate);
    }
    final shortened = candidate.substring(0, characterLimit).trimRight();
    if (RegExp(r'[。！？!?]$').hasMatch(shortened)) return shortened;
    return '$shortened…';
  }

  static String _removeModelArtifacts(String reply) {
    return reply
        .replaceAll(
          RegExp(r'<think>[\s\S]*?(?:</think>|$)', caseSensitive: false),
          ' ',
        )
        .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
        .replaceAll(
          RegExp(
            r'^\s*(?:assistant|回覆|答覆)\s*[:：]\s*',
            caseSensitive: false,
            multiLine: true,
          ),
          '',
        )
        .replaceAll(RegExp(r'[=*_#~─━-]{3,}[^\r\n]*'), ' ')
        .replaceAll(RegExp(r'([。！？!?])\1+'), r'$1')
        .trim();
  }

  static String _ensureSentenceEnding(String value) {
    if (value.isEmpty || RegExp(r'[。！？!?…]$').hasMatch(value)) {
      return value;
    }
    return '$value。';
  }

  static String _enforceChineseForChineseInput({
    required String sourceText,
    required String reply,
  }) {
    final containsChineseInput = RegExp(
      r'[\u3400-\u9fff]',
    ).hasMatch(sourceText);
    if (!containsChineseInput || !RegExp(r'[A-Za-z]').hasMatch(reply)) {
      return reply;
    }

    var sanitized = reply
        .replaceAll(
          RegExp(r'sounds?\s+good[.!?\s]*', caseSensitive: false),
          '聽起來不錯！',
        )
        .replaceAll(
          RegExp(r'\b(?:ok(?:ay)?|sure)\b', caseSensitive: false),
          '好的',
        )
        .replaceAll(RegExp(r'\bhello\b', caseSensitive: false), '你好')
        .replaceAll(RegExp(r'[A-Za-z]+(?:[\u2019\x27_-][A-Za-z]+)*'), '')
        .replaceAll(RegExp(r'\s+([，。！？、：；])'), r'$1')
        .replaceAll(RegExp(r'^[\s，。！？、：；,.!?;:\-]+'), '')
        .trim();

    if (!RegExp(r'[\u3400-\u9fff]').hasMatch(sanitized)) {
      sanitized = '我剛剛沒有整理好中文回覆，請再跟我說一次。';
    }
    return sanitized;
  }

  static bool _isBriefExchange(String sourceText) {
    final normalized = sourceText
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[，。！？,.!?]'), '');
    if (normalized.length > 12) return false;
    return const <String>[
      '早安',
      '早上好',
      '午安',
      '晚安',
      '你好',
      '嗨',
      '哈囉',
      'hello',
      '謝謝',
      '感謝',
      '掰掰',
      '再見',
    ].any(normalized.contains);
  }
}
