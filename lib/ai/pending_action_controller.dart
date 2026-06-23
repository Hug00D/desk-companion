import '../voice/voice_command.dart';

class PendingCompanionAction {
  const PendingCompanionAction({
    required this.command,
    required this.confirmationText,
    this.createdAt,
    this.ttl = const Duration(seconds: 45),
  });

  final VoiceCommand command;
  final String confirmationText;
  final DateTime? createdAt;
  final Duration ttl;

  bool isExpired(DateTime now) {
    final timestamp = createdAt;
    if (timestamp == null) return false;
    return now.difference(timestamp) > ttl;
  }
}

enum PendingActionResolutionType { accepted, declined }

class PendingActionResolution {
  const PendingActionResolution({required this.type, required this.action});

  final PendingActionResolutionType type;
  final PendingCompanionAction action;
}

class PendingActionController {
  PendingCompanionAction? _pending;

  PendingCompanionAction? get pending => _pending;

  void set(PendingCompanionAction action, {DateTime? now}) {
    _pending = PendingCompanionAction(
      command: action.command,
      confirmationText: action.confirmationText,
      createdAt: now ?? DateTime.now(),
      ttl: action.ttl,
    );
  }

  void clear() {
    _pending = null;
  }

  PendingActionResolution? resolve(String userText, {DateTime? now}) {
    final action = _pending;
    if (action == null) return null;

    final timestamp = now ?? DateTime.now();
    if (action.isExpired(timestamp)) {
      clear();
      return null;
    }

    final normalized = _normalize(userText);
    if (normalized.isEmpty) return null;

    if (_containsAny(normalized, _declinePhrases)) {
      clear();
      return PendingActionResolution(
        type: PendingActionResolutionType.declined,
        action: action,
      );
    }

    if (_containsAny(normalized, _acceptPhrases)) {
      clear();
      return PendingActionResolution(
        type: PendingActionResolutionType.accepted,
        action: action,
      );
    }

    return null;
  }

  bool _containsAny(String normalizedText, List<String> phrases) {
    return phrases.any((phrase) => normalizedText.contains(_normalize(phrase)));
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[\uFF0C\u3002\uFF01\uFF1F,.!?]'), '');
  }
}

const List<String> _acceptPhrases = [
  '好',
  '可以',
  '開始',
  '開始吧',
  '對',
  '沒錯',
  '幫我',
  'yes',
  'ok',
  'okay',
];

const List<String> _declinePhrases = [
  '不要',
  '不用',
  '取消',
  '先不要',
  '不是',
  '等一下',
  'no',
  'cancel',
];
