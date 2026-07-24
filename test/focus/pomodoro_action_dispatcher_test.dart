import 'package:desk_companion/focus/focus_session_monitor.dart';
import 'package:desk_companion/focus/pomodoro_action_dispatcher.dart';
import 'package:desk_companion/focus/pomodoro_controller.dart';
import 'package:desk_companion/focus/study_session_controller.dart';
import 'package:desk_companion/voice/voice_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('focus summary uses the same live metrics as the tasks panel', () {
    final pomodoroController = PomodoroController();
    final focusSessionMonitor = FocusSessionMonitor.detached()
      ..effectiveFocusDuration = const Duration(seconds: 30)
      ..distractedDuration = const Duration(seconds: 12);
    final studySessionController = StudySessionController();
    const dispatcher = PomodoroActionDispatcher();

    final result = dispatcher.dispatch(
      command: const VoiceCommand(
        type: VoiceCommandType.requestFocusSummary,
        sourceText: '查看專注摘要',
      ),
      controller: pomodoroController,
      studySession: studySessionController,
      focusSessionMonitor: focusSessionMonitor,
    );

    expect(result.response.message, contains('有效專注 30 秒'));
    expect(result.response.message, contains('分心 12 秒'));
    expect(result.response.message, contains('專注事件 0 次'));
  });
}
