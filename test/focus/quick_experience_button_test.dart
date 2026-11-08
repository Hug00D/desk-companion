import 'package:desk_companion/focus/pomodoro_controller.dart';
import 'package:desk_companion/widgets/quick_experience_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final controller = PomodoroController();

  setUp(controller.stop);
  tearDown(controller.stop);

  Widget buildButton(VoidCallback onPressed, {VoidCallback? onOpenPomodoro}) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: QuickExperienceButton(
            controller: controller,
            onPressed: onPressed,
            onOpenPomodoro: onOpenPomodoro ?? () {},
          ),
        ),
      ),
    );
  }

  testWidgets('first tap only expands, next tap starts the experience', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(buildButton(() => presses++));

    expect(find.text('1 分鐘快速體驗'), findsNothing);
    expect(
      tester.getSize(find.byType(QuickExperienceButton)),
      const Size(48, 48),
    );
    await tester.tap(find.byKey(const ValueKey('quick-experience-toggle')));
    await tester.pumpAndSettle();
    expect(presses, 0);
    expect(find.text('1 分鐘快速體驗'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('quick-experience-action')));

    expect(presses, 1);
  });

  for (final paused in [false, true]) {
    testWidgets('opens the existing ${paused ? "paused" : "running"} round', (
      tester,
    ) async {
      controller.start(durationMinutes: 25);
      if (paused) controller.pause();
      final originalStatus = controller.status;
      var starts = 0;
      var opens = 0;
      await tester.pumpWidget(
        buildButton(() => starts++, onOpenPomodoro: () => opens++),
      );
      expect(find.text('專注場次進行中'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('quick-experience-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('專注場次進行中'), findsOneWidget);
      expect(opens, 0);
      await tester.tap(find.byKey(const ValueKey('quick-experience-action')));
      expect(starts, 0);
      expect(opens, 1);
      expect(controller.status, originalStatus);
      expect(controller.totalDuration, const Duration(minutes: 25));
      controller.stop();
      await tester.pump();
    });
  }

  testWidgets('running timer updates do not prevent automatic collapse', (
    tester,
  ) async {
    controller.start(durationMinutes: 25);
    await tester.pumpWidget(buildButton(() {}));
    await tester.tap(find.byKey(const ValueKey('quick-experience-toggle')));
    await tester.pump();
    for (var second = 0; second < 3; second++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pumpAndSettle();
    expect(find.text('專注場次進行中'), findsNothing);
    expect(controller.isRunning, isTrue);
    controller.stop();
    await tester.pump();
  });

  testWidgets(
    'updates the expanded action when a round starts, and can collapse',
    (tester) async {
      var opens = 0;
      await tester.pumpWidget(
        buildButton(
          () => controller.start(durationMinutes: 1),
          onOpenPomodoro: () => opens++,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('quick-experience-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('quick-experience-action')));
      await tester.pumpAndSettle();
      expect(controller.totalDuration, const Duration(minutes: 1));
      expect(find.text('專注場次進行中'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('quick-experience-action')));
      expect(opens, 1);
      await tester.tap(find.byKey(const ValueKey('quick-experience-collapse')));
      await tester.pumpAndSettle();
      expect(find.text('專注場次進行中'), findsNothing);
      expect(controller.isRunning, isTrue);
      controller.stop();
      await tester.pump();
    },
  );
}
