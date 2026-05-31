import 'voice_command.dart';
import 'voice_result.dart';

class VoiceCommandParser {
  const VoiceCommandParser({
    this.minimumConfidence = 0.45,
    this.defaultPomodoroMinutes = 25,
  });

  final double minimumConfidence;
  final int defaultPomodoroMinutes;

  VoiceCommand parse(VoiceRecognitionResult result) {
    if (result.hasError) {
      return VoiceCommand(
        type: VoiceCommandType.ignored,
        sourceText: '',
        reason: result.error?.message ?? 'Voice recognition failed.',
      );
    }

    if (!result.isFinal) {
      return VoiceCommand(
        type: VoiceCommandType.ignored,
        sourceText: result.bestText,
        confidence: result.bestConfidence,
        reason: 'Waiting for final recognition result.',
      );
    }

    final textPool = _buildTextPool(result);
    final sourceText = result.bestText;
    final bestConfidence = result.bestConfidence;

    if (bestConfidence != null && bestConfidence < minimumConfidence) {
      return VoiceCommand(
        type: VoiceCommandType.unknown,
        sourceText: sourceText,
        confidence: bestConfidence,
        reason: 'Recognition confidence is too low.',
      );
    }

    if (_containsAny(textPool, _stopKeywords)) {
      return VoiceCommand(
        type: VoiceCommandType.stopPomodoro,
        sourceText: sourceText,
        confidence: bestConfidence,
      );
    }

    if (_containsAny(textPool, _pauseKeywords)) {
      return VoiceCommand(
        type: VoiceCommandType.pausePomodoro,
        sourceText: sourceText,
        confidence: bestConfidence,
      );
    }

    if (_containsAny(textPool, _resumeKeywords)) {
      return VoiceCommand(
        type: VoiceCommandType.resumePomodoro,
        sourceText: sourceText,
        confidence: bestConfidence,
      );
    }

    if (_containsAny(textPool, _summaryKeywords)) {
      return VoiceCommand(
        type: VoiceCommandType.requestFocusSummary,
        sourceText: sourceText,
        confidence: bestConfidence,
      );
    }

    final hasPomodoroKeyword = _containsAny(textPool, _pomodoroKeywords);
    final hasStartKeyword = _containsAny(textPool, _startKeywords);
    final hasFocusProblemKeyword = _containsAny(
      textPool,
      _focusProblemKeywords,
    );

    if (hasPomodoroKeyword || (hasStartKeyword && hasFocusProblemKeyword)) {
      return VoiceCommand(
        type: VoiceCommandType.startPomodoro,
        sourceText: sourceText,
        confidence: bestConfidence,
        durationMinutes:
            _extractDurationMinutes(textPool) ?? defaultPomodoroMinutes,
      );
    }

    return VoiceCommand(
      type: VoiceCommandType.unknown,
      sourceText: sourceText,
      confidence: bestConfidence,
      reason: 'No command rule matched.',
    );
  }

  List<String> _buildTextPool(VoiceRecognitionResult result) {
    return [
      result.bestText,
      if (result.transcript != null) result.transcript!,
      if (result.formattedTranscript != null) result.formattedTranscript!,
      ...result.candidates.map((candidate) => candidate.text),
      for (final span in result.alternatives) ...span.texts,
    ].map(_normalize).where((text) => text.isNotEmpty).toList();
  }

  bool _containsAny(List<String> textPool, List<String> keywords) {
    return textPool.any(
      (text) => keywords.any((keyword) => text.contains(_normalize(keyword))),
    );
  }

  int? _extractDurationMinutes(List<String> textPool) {
    for (final text in textPool) {
      final digitMatch = RegExp(r'(\d{1,3})\s*\u5206').firstMatch(text);
      if (digitMatch != null) {
        return int.tryParse(digitMatch.group(1)!);
      }

      for (final entry in _chineseMinuteValues.entries) {
        if (text.contains(entry.key)) return entry.value;
      }
    }

    return null;
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[\uFF0C\u3002\uFF01\uFF1F,.!?]'), '');
  }
}

const List<String> _pauseKeywords = [
  '\u66ab\u505c',
  '\u505c\u4e00\u4e0b',
  '\u5148\u7b49\u4e00\u4e0b',
  '\u4f11\u606f\u4e00\u4e0b',
  '\u5148\u4f11\u606f',
];

const List<String> _stopKeywords = [
  '\u505c\u6b62',
  '\u4e2d\u6b62',
  '\u4e0d\u8981\u8a08\u6642',
  '\u7d50\u675f\u756a\u8304\u9418',
  '\u95dc\u6389\u756a\u8304\u9418',
  '\u53d6\u6d88\u756a\u8304\u9418',
];

const List<String> _resumeKeywords = [
  '\u7e7c\u7e8c',
  '\u6062\u5fa9',
  '\u6211\u56de\u4f86\u4e86',
  '\u63a5\u8457',
];

const List<String> _summaryKeywords = [
  '\u6458\u8981',
  '\u72c0\u614b',
  '\u4eca\u5929',
  '\u5c08\u6ce8\u72c0\u614b',
];

const List<String> _pomodoroKeywords = [
  '\u756a\u8304\u9418',
  '\u756a\u8304\u4e2d',
  '\u5c08\u6ce8\u9418',
  '\u5c08\u6ce8\u6642\u9593',
];

const List<String> _startKeywords = [
  '\u958b\u59cb',
  '\u8a2d\u7f6e',
  '\u8a2d\u5b9a',
  '\u5e6b\u6211',
];

const List<String> _focusProblemKeywords = ['\u5c08\u6ce8', '\u5206\u5fc3'];

const Map<String, int> _chineseMinuteValues = {
  '\u4e94\u5206\u9418': 5,
  '\u5341\u5206\u9418': 10,
  '\u5341\u4e94\u5206\u9418': 15,
  '\u4e8c\u5341\u5206\u9418': 20,
  '\u4e8c\u5341\u4e94\u5206\u9418': 25,
  '\u4e09\u5341\u5206\u9418': 30,
  '\u56db\u5341\u4e94\u5206\u9418': 45,
  '\u4e00\u5c0f\u6642': 60,
};
