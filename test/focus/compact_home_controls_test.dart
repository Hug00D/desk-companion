import 'package:desk_companion/focus/pomodoro_controller.dart';
import 'package:desk_companion/widgets/quick_experience_button.dart';
import 'package:desk_companion/widgets/vision_source_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scale in [1.0, 1.6]) {
    testWidgets(
      'controls expand and remain usable on a narrow screen at $scale',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(320, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var starts = 0;
        var retries = 0;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    QuickExperienceButton(
                      controller: PomodoroController(),
                      onPressed: () => starts++,
                      onOpenPomodoro: () {},
                    ),
                    const SizedBox(height: 8),
                    VisionSourceIndicator(
                      status: VisionSourceStatus.video,
                      onRetryCamera: () => retries++,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('quick-experience-toggle')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('vision-source-toggle')));
        await tester.pumpAndSettle();
        expect(starts, 0);
        expect(retries, 0);
        await tester.tap(find.text('重試相機'));
        expect(retries, 1);
        await tester.tap(find.byKey(const ValueKey('quick-experience-action')));
        expect(starts, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
