import 'package:desk_companion/focus/pomodoro_action_dispatcher.dart';
import 'package:desk_companion/focus/pomodoro_controller.dart';
import 'package:desk_companion/voice/voice_command.dart';
import 'package:desk_companion/voice/voice_command_parser.dart';
import 'package:desk_companion/voice/voice_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Chinese voice command parser', () {
    const parser = VoiceCommandParser();

    test('starts a custom pomodoro from Chinese speech text', () {
      final command = parser.parse(_voiceResult('幫我開始十五分鐘番茄鐘'));

      expect(command.type, VoiceCommandType.startPomodoro);
      expect(command.durationMinutes, 15);

      final pomodoroController = PomodoroController();
      const dispatcher = PomodoroActionDispatcher();
      final actionResult = dispatcher.dispatch(
        command: command,
        controller: pomodoroController,
      );

      expect(actionResult.shouldStartTimer, isTrue);
      expect(pomodoroController.status, PomodoroStatus.running);
      expect(pomodoroController.remaining, const Duration(minutes: 15));
    });

    test('maps common Chinese timer controls', () {
      expect(
        parser.parse(_voiceResult('先幫我暫停番茄鐘')).type,
        VoiceCommandType.pausePomodoro,
      );
      expect(
        parser.parse(_voiceResult('我回來了繼續番茄鐘')).type,
        VoiceCommandType.resumePomodoro,
      );
      expect(
        parser.parse(_voiceResult('中止番茄鐘')).type,
        VoiceCommandType.stopPomodoro,
      );
      expect(
        parser.parse(_voiceResult('現在番茄鐘還剩多久')).type,
        VoiceCommandType.requestTimerStatus,
      );
    });

    test('does not block Chinese commands when confidence is unavailable', () {
      final command = parser.parse(_voiceResult('幫我開始番茄鐘'));

      expect(command.type, VoiceCommandType.startPomodoro);
      expect(command.durationMinutes, 25);
    });

    test('does not start when text only mentions pomodoro status', () {
      final command = parser.parse(
        _voiceResult(
          '\u4f60\u5e6b\u6211\u958b\u59cb\u8a08\u6642\u4e86\u4f46\u756a\u8304\u9418\u4f3c\u4e4e\u6c92\u5728\u52d5',
        ),
      );

      expect(command.type, VoiceCommandType.unknown);
    });

    test(
      'asks for confirmation when a low confidence result resembles pomodoro',
      () {
        final command = parser.parse(_voiceResult('幫我設定番茄鐘', confidence: 0.2));

        expect(command.type, VoiceCommandType.confirmStartPomodoro);
        expect(command.durationMinutes, 25);
      },
    );
  });
}

VoiceRecognitionResult _voiceResult(String text, {double? confidence}) {
  return VoiceRecognitionResult(
    sessionId: 'test_voice',
    eventType: VoiceEventType.finalResult,
    timestampMs: 0,
    transcript: text,
    formattedTranscript: text,
    isFinal: true,
    candidates: [VoiceCandidate(text: text, confidence: confidence)],
    audio: const VoiceAudioInfo(isSpeechDetected: true),
    language: const VoiceLanguageInfo(tag: 'zh_TW'),
  );
}
