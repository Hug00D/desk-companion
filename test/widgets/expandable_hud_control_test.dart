import 'package:desk_companion/widgets/expandable_hud_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget control({Widget? action}) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: ExpandableHudControl(
          controlId: 'test-control',
          icon: Icons.videocam_rounded,
          label: '即時相機',
          detail: '來源說明',
          color: Colors.blue,
          semanticName: '相機來源',
          expandedAction: action,
        ),
      ),
    ),
  );

  testWidgets('collapses after three idle seconds', (tester) async {
    await tester.pumpWidget(control());
    await tester.tap(find.byKey(const ValueKey('test-control-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2900));
    expect(find.text('即時相機'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('即時相機'), findsNothing);
    expect(
      tester.getSize(find.byType(ExpandableHudControl)),
      const Size(48, 48),
    );
  });

  testWidgets('action interaction restarts the idle countdown', (tester) async {
    var actions = 0;
    await tester.pumpWidget(
      control(
        action: TextButton(
          onPressed: () => actions++,
          child: const Text('重新校正'),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('test-control-toggle')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('重新校正'));
    await tester.pump();
    expect(actions, 1);
    await tester.pump(const Duration(milliseconds: 2900));
    expect(find.text('即時相機'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(find.text('即時相機'), findsNothing);
  });

  testWidgets('holding a control delays collapse until after release', (
    tester,
  ) async {
    await tester.pumpWidget(
      control(
        action: TextButton(onPressed: () {}, child: const Text('重新校正')),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('test-control-toggle')));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('重新校正')),
    );
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('即時相機'), findsOneWidget);
    await gesture.up();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('即時相機'), findsNothing);
  });
}
