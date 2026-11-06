import 'package:desk_companion/preferences/companion_preferences.dart';
import 'package:desk_companion/preferences/companion_preferences_controller.dart';
import 'package:desk_companion/screens/profile_hub_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final controller = CompanionPreferencesController.instance;

  setUp(() {
    final original = controller.value;
    controller.value = const CompanionPreferences();
    addTearDown(() => controller.value = original);
  });

  testWidgets(
    'settings changes shared preferences and retains them on reopen',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: ProfileHubScreen()));

      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(controller.value.quietMode, isTrue);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

      await tester.tap(find.text('AI 回覆語氣'));
      await tester.pump();
      expect(controller.value.aiResponseTone, AiResponseTone.encouraging);
      expect(find.text('目前：鼓勵，點擊切換語氣。'), findsOneWidget);
      expect(find.text('提醒敏感度'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(const MaterialApp(home: ProfileHubScreen()));
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      expect(find.text('目前：鼓勵，點擊切換語氣。'), findsOneWidget);
    },
  );

  testWidgets('settings observes changes made through the shared controller', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: ProfileHubScreen()));

    controller.setQuietMode(true);
    controller.cycleResponseTone();
    controller.cycleResponseTone();
    await tester.pump();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    expect(find.text('目前：嚴格，點擊切換語氣。'), findsOneWidget);

    await tester.tap(find.text('安靜模式'));
    await tester.pump();
    expect(controller.value.quietMode, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });
}
