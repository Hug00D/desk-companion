import 'package:desk_companion/focus/pomodoro_controller.dart';
import 'package:desk_companion/widgets/quick_experience_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final controller = PomodoroController();

  setUp(controller.stop);
  tearDown(controller.stop);

  Widget buildButton(VoidCallback onPressed) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: QuickExperienceButton(
            controller: controller,
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }

  testWidgets('shows an explicit one-minute action and invokes it', (
    tester,
  ) async {
    var presses = 0;
    await tester.pumpWidget(buildButton(() => presses++));

    expect(find.text('1 分鐘快速體驗'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('quick-experience-button')));

    expect(presses, 1);
  });

  testWidgets('reflects an active focus session', (tester) async {
    controller.start(durationMinutes: 1);
    await tester.pumpWidget(buildButton(() {}));

    expect(find.text('專注場次進行中'), findsOneWidget);
    expect(find.byIcon(Icons.timer_rounded), findsOneWidget);

    controller.stop();
    await tester.pump();
  });
}
