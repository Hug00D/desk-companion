import 'package:desk_companion/widgets/vision_source_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('fallback offers a camera retry and changes to live source', (
    tester,
  ) async {
    var status = VisionSourceStatus.video;
    var retries = 0;
    late StateSetter update;
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Padding(
                padding: const EdgeInsets.all(18),
                child: VisionSourceIndicator(
                  status: status,
                  isCalibrating: true,
                  onRetryCamera: () {
                    retries++;
                    setState(() => status = VisionSourceStatus.initializing);
                  },
                ),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('測試影片'), findsOneWidget);
    await tester.tap(find.text('重試相機'));
    await tester.pump();
    expect(retries, 1);
    expect(find.text('正在啟動…'), findsOneWidget);
    expect(find.text('重試相機'), findsNothing);

    update(() => status = VisionSourceStatus.camera);
    await tester.pump();
    expect(find.text('即時相機・校正中'), findsOneWidget);
    expect(find.text('測試影片'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unavailable source exposes a retry action', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VisionSourceIndicator(
            status: VisionSourceStatus.unavailable,
            onRetryCamera: () => retried = true,
          ),
        ),
      ),
    );

    expect(find.text('未就緒'), findsOneWidget);
    await tester.tap(find.text('重試相機'));
    expect(retried, isTrue);
  });
}
