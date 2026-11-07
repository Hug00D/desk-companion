import 'package:desk_companion/focus/pomodoro_controller.dart';
import 'package:desk_companion/screens/tasks_screen.dart';
import 'package:desk_companion/widgets/pomodoro_dock_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final controller = PomodoroController();

  setUp(() {
    controller.stop();
    addTearDown(controller.stop);
  });

  Widget buildPanel({required VoidCallback onOpen}) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 184,
            height: 52,
            child: PomodoroDockPanel(controller: controller, onTap: onOpen),
          ),
        ),
      ),
    );
  }

  testWidgets('idle panel opens tasks without showing a toggle', (
    tester,
  ) async {
    var opens = 0;
    await tester.pumpWidget(buildPanel(onOpen: () => opens++));

    expect(find.text('開始專注'), findsOneWidget);
    expect(find.byKey(const ValueKey('pomodoro-dock-toggle')), findsNothing);

    await tester.tap(find.text('開始專注'));
    expect(opens, 1);
  });

  testWidgets('running panel pauses and resumes without opening tasks', (
    tester,
  ) async {
    var opens = 0;
    controller.start(durationMinutes: 1);
    await tester.pumpWidget(buildPanel(onOpen: () => opens++));

    expect(find.text('番茄鐘・專注中'), findsOneWidget);
    await tester.tap(find.byTooltip('暫停番茄鐘'));
    await tester.pump();

    expect(controller.status, PomodoroStatus.paused);
    expect(controller.pauseReason, PomodoroPauseReason.manual);
    expect(find.text('番茄鐘・已暫停'), findsOneWidget);
    expect(opens, 0);

    final pausedRemaining = controller.remaining;
    await tester.pumpWidget(const MaterialApp(home: TasksScreen()));
    await tester.pump();
    expect(find.text('已暫停'), findsOneWidget);
    expect(controller.remaining, pausedRemaining);

    await tester.pumpWidget(buildPanel(onOpen: () => opens++));
    await tester.pump();

    await tester.tap(find.byTooltip('繼續番茄鐘'));
    await tester.pump();

    expect(controller.status, PomodoroStatus.running);
    expect(controller.pauseReason, isNull);
    expect(find.text('番茄鐘・專注中'), findsOneWidget);
    expect(opens, 0);

    controller.stop();
    await tester.pump();
  });
}
