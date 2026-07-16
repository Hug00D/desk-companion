import '../voice/voice_command.dart';

class PendingAction {
  const PendingAction({required this.command, required this.confirmationText});

  final VoiceCommand command;
  final String confirmationText;
}

class PendingActionController {
  PendingAction? _pendingAction;

  PendingAction? get pendingAction => _pendingAction;

  bool get hasPendingAction => _pendingAction != null;

  void setPendingAction(PendingAction action) {
    _pendingAction = action;
  }

  PendingAction? consume() {
    final action = _pendingAction;
    _pendingAction = null;
    return action;
  }

  void clear() {
    _pendingAction = null;
  }
}
