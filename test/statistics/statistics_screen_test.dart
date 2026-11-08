import 'dart:convert';

import 'package:desk_companion/api/api_client.dart';
import 'package:desk_companion/api/statistics_api.dart';
import 'package:desk_companion/api/focus_api.dart';
import 'package:desk_companion/auth/auth_session.dart';
import 'package:desk_companion/focus/focus_sync_controller.dart';
import 'package:desk_companion/focus/pomodoro_controller.dart';
import 'package:desk_companion/focus/study_session_controller.dart';
import 'package:desk_companion/focus/focus_report_history.dart';
import 'package:desk_companion/screens/focus_report_history_screen.dart';
import 'package:desk_companion/screens/statistics_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _EmptyLocalHistory extends FocusReportHistoryRepository {
  @override
  Future<List<FocusReportRecord>> list({required String? userId}) async => [];
}

void main() {
  testWidgets(
    'only a failed upload shows a notice, and refresh clears it after recovery',
    (tester) async {
      final auth = AuthSession.instance;
      auth.setSession(userId: 'stats-user', email: 'stats@example.test');
      addTearDown(auth.clear);
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var online = false;
      final client = ApiClient(
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/statistics')) {
            return http.Response(
              '{"today":{"focusSeconds":48,"completedRoundCount":1}}',
              200,
            );
          }
          if (!online) return http.Response('{"message":"offline"}', 503);
          return http.Response('{"sessionId":"test-session"}', 200);
        }),
      );
      final sync = FocusSyncController(
        authSession: auth,
        focusApi: FocusApi(client),
      );
      sync.start(
        studySessionController: StudySessionController(),
        pomodoroController: PomodoroController(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: StatisticsScreen(
            statisticsApi: StatisticsApi(client),
            syncController: sync,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('部分專注紀錄尚未同步'), findsOneWidget);
      expect(find.text('同步'), findsNothing);
      expect(find.text('重試'), findsNothing);

      online = true;
      await tester.tap(find.byIcon(Icons.refresh_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text('部分專注紀錄尚未同步'), findsNothing);
      expect(find.text('專注紀錄已同步'), findsNothing);
      expect(find.text('同步'), findsNothing);
      expect(find.text('完成輪數'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      sync.dispose();
    },
  );

  testWidgets(
    'statistics presents a service error and reloads after recovery',
    (tester) async {
      final auth = AuthSession.instance;
      auth.setSession(userId: 'stats-user', email: 'stats@example.test');
      addTearDown(auth.clear);
      await tester.binding.setSurfaceSize(const Size(430, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var online = false;
      final api = StatisticsApi(
        ApiClient(
          httpClient: MockClient((_) async {
            if (!online) {
              return http.Response('{"message":"internal error"}', 503);
            }
            return http.Response(
              jsonEncode({
                'today': {'focusSeconds': 48, 'completedRoundCount': 1},
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: StatisticsScreen(
            statisticsApi: api,
            historyRepository: _EmptyLocalHistory(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('統計載入失敗'), findsOneWidget);
      expect(find.text('服務暫時無法使用，請稍後重試。'), findsOneWidget);
      await tester.tap(find.text('逐輪評分紀錄'));
      await tester.pumpAndSettle();
      expect(find.byType(FocusReportHistoryScreen), findsOneWidget);
      expect(find.textContaining('還沒有保存的評分表'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      online = true;
      await tester.tap(find.text('重新整理'));
      await tester.pumpAndSettle();
      expect(find.text('統計載入失敗'), findsNothing);
      expect(find.text('完成輪數'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
