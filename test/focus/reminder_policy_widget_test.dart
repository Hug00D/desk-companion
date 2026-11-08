import 'package:desk_companion/focus/focus_session_monitor.dart';
import 'package:desk_companion/preferences/companion_preferences_controller.dart';
import 'package:desk_companion/screens/tasks_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tasks screen enables the conservative reminder pilot', (
    tester,
  ) async {
    final monitor = FocusSessionMonitor();
    monitor.setExperimentalReminderPolicyEnabled(false);
    addTearDown(() {
      monitor.setExperimentalReminderPolicyEnabled(false);
    });

    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: TasksScreen()));

    expect(find.text('保守提醒試用'), findsOneWidget);
    expect(find.text('嚴重狀況自動暫停'), findsOneWidget);
    expect(find.textContaining('安靜模式只會停止主動語音與提醒詢問'), findsOneWidget);

    await tester.tap(find.byType(Switch).first);
    await tester.pump();

    expect(monitor.experimentalReminderPolicyEnabled, isTrue);
    expect(find.text('嚴重狀況自動暫停'), findsNothing);
    expect(find.byType(Switch), findsOneWidget);
  });

  test('quiet mode does not alter task auto-pause switches', () {
    final monitor = FocusSessionMonitor()
      ..setExperimentalReminderPolicyEnabled(false)
      ..setSevereAutoPauseEnabled(false)
      ..setLongDistractionAutoPauseEnabled(true);
    final preferences = CompanionPreferencesController.instance;
    final originalPreferences = preferences.value;
    addTearDown(() {
      preferences.value = originalPreferences;
      monitor.setSevereAutoPauseEnabled(true);
      monitor.setLongDistractionAutoPauseEnabled(false);
    });

    preferences.setQuietMode(true);

    expect(monitor.severeAutoPauseEnabled, isFalse);
    expect(monitor.longDistractionAutoPauseEnabled, isTrue);
    expect(monitor.experimentalReminderPolicyEnabled, isFalse);
  });

  testWidgets('tasks screen shows only the available Pomodoro mode', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: TasksScreen()));

    expect(find.text('目前使用中的專注模式'), findsOneWidget);
    expect(find.text('自由專注'), findsNothing);
    expect(find.text('閱讀模式'), findsNothing);
    expect(find.text('護眼休息'), findsNothing);
    expect(find.textContaining('準備中'), findsNothing);
  });
}
