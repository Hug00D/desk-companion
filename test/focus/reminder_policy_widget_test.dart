import 'package:desk_companion/focus/focus_session_monitor.dart';
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

    await tester.tap(find.byType(Switch).first);
    await tester.pump();

    expect(monitor.experimentalReminderPolicyEnabled, isTrue);
    expect(find.text('嚴重狀況自動暫停'), findsNothing);
    expect(find.byType(Switch), findsOneWidget);
  });
}
