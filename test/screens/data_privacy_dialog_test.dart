import 'package:desk_companion/widgets/data_privacy_dialog.dart';
import 'package:desk_companion/screens/profile_hub_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'settings opens a bounded dialog with fixed close and scrollable text',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: ProfileHubScreen()));
      await tester.ensureVisible(find.text('資料與隱私'));
      await tester.tap(find.text('資料與隱私'));
      await tester.pumpAndSettle();
      expect(find.byType(DataPrivacyDialog), findsOneWidget);
      expect(find.byType(ProfileHubScreen), findsOneWidget);
      expect(find.text('相機與偵測'), findsOneWidget);
      final card = tester.getRect(
        find.byKey(const ValueKey('data-privacy-card')),
      );
      expect(card.left, greaterThan(0));
      expect(card.top, greaterThan(0));
      expect(card.height, lessThan(900 * 0.8));
      expect(find.text('關閉').hitTestable(), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('保存與同步限制'),
        250,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('保存與同步限制').hitTestable(), findsOneWidget);
      await tester.tap(find.text('關閉'));
      await tester.pumpAndSettle();
      expect(find.byType(DataPrivacyDialog), findsNothing);
      expect(find.byType(ProfileHubScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('small screen and larger text retain a usable close button', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1.6)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDataPrivacyDialog(context),
              child: const Text('開啟說明'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('開啟說明'));
    await tester.pumpAndSettle();
    expect(find.text('關閉').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('關閉資料與隱私'));
    await tester.pumpAndSettle();
    expect(find.byType(DataPrivacyDialog), findsNothing);
  });
}
