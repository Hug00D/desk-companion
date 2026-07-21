import '../voice/voice_command.dart';

class PendingAction {
  const PendingAction({required this.command, required this.confirmationText});

  final VoiceCommand command;
  final String confirmationText;
}

class PendingCompanionAction extends PendingAction {
  const PendingCompanionAction({
    required super.command,
    required super.confirmationText,
    this.createdAt,
    this.ttl = const Duration(seconds: 45),
  });

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
  PendingAction? _pendingAction;

  PendingAction? get pendingAction => _pendingAction;

  PendingCompanionAction? get pending {
    final action = _pendingAction;
    if (action == null) return null;
    if (action is PendingCompanionAction) return action;
    return PendingCompanionAction(
      command: action.command,
      confirmationText: action.confirmationText,
    );
  }

  bool get hasPendingAction => _pendingAction != null;

  void setPendingAction(PendingAction action) {
    _pendingAction = action;
  }

  void set(PendingCompanionAction action, {DateTime? now}) {
    _pendingAction = PendingCompanionAction(
      command: action.command,
      confirmationText: action.confirmationText,
      createdAt: now ?? DateTime.now(),
      ttl: action.ttl,
    );
  }

  PendingAction? consume() {
    final action = _pendingAction;
    _pendingAction = null;
    return action;
  }

  void clear() {
    _pendingAction = null;
  }

  PendingActionResolution? resolve(String userText, {DateTime? now}) {
    final action = pending;
    if (action == null) return null;

    if (action.isExpired(now ?? DateTime.now())) {
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
