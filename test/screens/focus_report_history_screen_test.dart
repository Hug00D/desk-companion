import 'package:desk_companion/auth/auth_session.dart';
import 'package:desk_companion/focus/focus_report_history.dart';
import 'package:desk_companion/focus/focus_session_report.dart';
import 'package:desk_companion/screens/focus_report_history_screen.dart';
import 'package:desk_companion/vision/companion_state_evaluator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Reports extends FocusReportHistoryRepository {
  _Reports(this.records);
  final Map<String?, List<FocusReportRecord>> records;
  @override
  Future<List<FocusReportRecord>> list({required String? userId}) async =>
      records[userId] ?? [];
}

void main() {
  final auth = AuthSession.instance;
  setUp(() => auth.setSession(userId: 'user-a', email: 'a@example.test'));
  tearDown(auth.clear);

  testWidgets(
    'a user can reopen a specific round score sheet and retain an unscored round',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      FocusSessionReport report(int hour, int seconds) => FocusSessionReport(
        completedAt: DateTime(2026, 11, 8, hour),
        plannedDuration: const Duration(minutes: 1),
        effectiveFocusDuration: Duration(seconds: seconds),
        distractedDuration: Duration.zero,
        eventCounts: const <CompanionStatus, int>{},
      );
      final saved = report(18, 45);
      await tester.pumpWidget(
        MaterialApp(
          home: FocusReportHistoryScreen(
            repository: _Reports({
              'user-a': [
                FocusReportRecord(id: 'first', report: saved),
                FocusReportRecord(id: 'second', report: report(17, 5)),
              ],
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('75 分'), findsOneWidget);
      expect(find.text('資料不足'), findsOneWidget);
      await tester.tap(find.text('75 分'));
      await tester.pumpAndSettle();
      expect(find.text('專注評分報告'), findsOneWidget);
      expect(find.text(saved.feedback), findsOneWidget);
      expect(find.text('整輪有效專注比例'), findsOneWidget);
      expect(find.text('未觀測時間'), findsOneWidget);
      expect(find.text('資料涵蓋率 75%・未觀測不計入有效專注'), findsOneWidget);
      await tester.ensureVisible(find.text('關閉報告'));
      await tester.tap(find.text('關閉報告'));
      await tester.pumpAndSettle();
      expect(find.text('專注評分報告'), findsNothing);
      expect(find.text('資料不足'), findsOneWidget);

      auth.setSession(userId: 'user-b', email: 'b@example.test');
      await tester.pumpAndSettle();
      expect(find.text('75 分'), findsNothing);
      expect(find.textContaining('還沒有保存的評分表'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
