import 'package:desk_companion/ai/claude_intent_service.dart';
import 'package:desk_companion/ai/companion_ai_command_mapper.dart';
import 'package:desk_companion/ai/companion_ai_decision.dart';
import 'package:desk_companion/ai/pending_action_controller.dart';
import 'package:desk_companion/focus/pomodoro_action_dispatcher.dart';
import 'package:desk_companion/focus/pomodoro_controller.dart';
import 'package:desk_companion/voice/voice_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Claude-free AI intent flow', () {
    setUp(() => PomodoroController().stop());
    tearDown(() => PomodoroController().stop());

    test('Claude service stays disabled without an API key', () {
      final service = ClaudeIntentService(apiKey: '');

      expect(service.isEnabled, isFalse);
    });

    test('fake Claude decision maps to a confirmed pomodoro start', () {
      final decision = CompanionAiDecision.fromJson({
        'mode': 'action',
        'intent': 'start_pomodoro',
        'confidence': 0.93,
        'needsConfirmation': true,
        'confirmationText': '要幫你開始 25 分鐘番茄鐘嗎？',
        'chatReply': '可以，我先幫你準備。',
        'parameters': {'durationMinutes': 25},
      });
      const mapper = CompanionAiCommandMapper();
      final command = mapper.toVoiceCommand(
        sourceText: '幫我開始番茄鐘',
        decision: decision,
      );

      expect(command, isNotNull);
      expect(command!.type, VoiceCommandType.startPomodoro);
      expect(command.durationMinutes, 25);
      expect(mapper.requiresConfirmation(command.type), isTrue);

      final pendingController = PendingActionController();
      pendingController.set(
        PendingCompanionAction(
          command: command,
          confirmationText: decision.confirmationText,
        ),
      );

      final resolution = pendingController.resolve('好，開始吧');
      expect(resolution, isNotNull);
      expect(resolution!.type, PendingActionResolutionType.accepted);

      final pomodoroController = PomodoroController();
      const dispatcher = PomodoroActionDispatcher();
      final actionResult = dispatcher.dispatch(
        command: resolution.action.command,
        controller: pomodoroController,
      );

      expect(actionResult.shouldStartTimer, isTrue);
      expect(pomodoroController.status, PomodoroStatus.running);
      expect(pomodoroController.remaining, const Duration(minutes: 25));
    });

    test('declined confirmation does not execute the pending action', () {
      final decision = CompanionAiDecision.fromJson({
        'mode': 'action',
        'intent': 'start_pomodoro',
        'confidence': 0.91,
        'needsConfirmation': true,
        'confirmationText': '要幫你開始 25 分鐘番茄鐘嗎？',
        'chatReply': '',
        'parameters': {'durationMinutes': 25},
      });
      const mapper = CompanionAiCommandMapper();
      final command = mapper.toVoiceCommand(
        sourceText: '幫我開始番茄鐘',
        decision: decision,
      );

      final pendingController = PendingActionController();
      pendingController.set(
        PendingCompanionAction(
          command: command!,
          confirmationText: decision.confirmationText,
        ),
      );

      final resolution = pendingController.resolve('不要開始');

      expect(resolution, isNotNull);
      expect(resolution!.type, PendingActionResolutionType.declined);
      expect(PomodoroController().status, PomodoroStatus.idle);
    });

    test('chat decision does not become a voice command', () {
      final decision = CompanionAiDecision.fromJson({
        'mode': 'chat',
        'intent': 'none',
        'confidence': 0.86,
        'needsConfirmation': false,
        'confirmationText': '',
        'chatReply': '聽起來今天有點滿，我陪你慢慢整理。',
        'parameters': {'durationMinutes': 0},
      });
      const mapper = CompanionAiCommandMapper();

      expect(
        mapper.toVoiceCommand(sourceText: '我今天有點煩', decision: decision),
        isNull,
      );
    });
  });
}
