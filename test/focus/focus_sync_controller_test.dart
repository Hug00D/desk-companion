import 'dart:async';
import 'dart:convert';

import 'package:desk_companion/api/api_client.dart';
import 'package:desk_companion/api/focus_api.dart';
import 'package:desk_companion/api/statistics_api.dart';
import 'package:desk_companion/auth/auth_session.dart';
import 'package:desk_companion/focus/focus_round.dart';
import 'package:desk_companion/focus/focus_sync_controller.dart';
import 'package:desk_companion/focus/focus_sync_state.dart';
import 'package:desk_companion/focus/pomodoro_controller.dart';
import 'package:desk_companion/focus/study_session_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late _MemoryBackend backend;
  late FocusSyncController sync;
  late StudySessionController study;
  final timer = PomodoroController();
  final auth = AuthSession.instance;

  setUp(() {
    auth.setSession(userId: 'test-user', email: 'test@example.test');
    timer.stop();
    backend = _MemoryBackend();
    study = StudySessionController();
    sync = FocusSyncController(
      authSession: auth,
      focusApi: FocusApi(backend.client),
      eventBatchSize: 2,
    );
    sync.start(studySessionController: study, pomodoroController: timer);
  });
  tearDown(() {
    sync.dispose();
    timer.stop();
    auth.clear();
  });

  Future<void> startRound() async {
    timer.start(durationMinutes: 1);
    await sync.startFocusRound(
      studySessionController: study,
      pomodoroController: timer,
    );
  }

  Future<void> completeRound() => sync.updateCurrentRound(
    status: FocusRoundStatus.completed,
    endedAt: DateTime.now().add(const Duration(minutes: 1)),
    endReason: FocusRoundEndReason.completed,
    studySessionController: study,
    pomodoroController: timer,
  );

  test(
    'completed round, session time and events reach the statistics API',
    () async {
      await startRound();
      study.focusedDuration = const Duration(seconds: 48);
      await completeRound();
      await sync.uploadDemoEvent(
        studySessionController: study,
        pomodoroController: timer,
      );
      expect(await sync.retrySync(), isTrue);
      final summary = await StatisticsApi(backend.client).getMySummary(
        authSession: auth,
        from: DateTime.now().subtract(const Duration(days: 1)),
        to: DateTime.now(),
        timezone: 'Asia/Taipei',
      );
      expect(summary.today.focusSeconds, 48);
      expect(summary.today.completedRoundCount, 1);
      expect(backend.events, hasLength(1));
      expect(sync.syncState.phase, FocusSyncPhase.synced);
    },
  );

  test(
    'a failed terminal round update stays pending and retry does not recreate it',
    () async {
      await startRound();
      backend.failRoundUpdate = true;
      await completeRound();
      expect(sync.syncState.phase, FocusSyncPhase.failed);
      expect(sync.syncState.pendingRounds, 1);
      expect(backend.rounds.values.single['status'], 'active');

      backend.failRoundUpdate = false;
      expect(await sync.retrySync(), isTrue);
      expect(backend.rounds, hasLength(1));
      expect(backend.roundCreates, 1);
      expect(backend.rounds.values.single['status'], 'completed');
      expect(sync.syncState.pendingRounds, 0);
    },
  );

  test(
    'round completed during a connection outage survives until retry',
    () async {
      backend.offline = true;
      await startRound();
      await completeRound();
      expect(sync.syncState.phase, FocusSyncPhase.failed);
      expect(sync.syncState.pendingRounds, 1);
      backend.offline = false;
      expect(await sync.retrySync(), isTrue);
      expect(backend.rounds.values.single['status'], 'completed');
    },
  );

  test(
    'completion arriving during slow round creation is not overwritten',
    () async {
      backend.roundGate = Completer<void>();
      final starting = startRound();
      await backend.roundRequested.future;
      final completing = completeRound();
      backend.roundGate!.complete();
      await Future.wait([starting, completing]);
      expect(await sync.retrySync(), isTrue);
      expect(backend.rounds.values.single['status'], 'completed');
      expect(backend.roundCreates, 1);
    },
  );

  test(
    'retry drains multiple batches and a missing acknowledgement keeps events',
    () async {
      backend.failEvents = true;
      for (var i = 0; i < 5; i++) {
        await sync.uploadDemoEvent(
          studySessionController: study,
          pomodoroController: timer,
        );
      }
      expect(sync.syncState.pendingEvents, 5);
      backend.failEvents = false;
      backend.incompleteAcknowledgement = true;
      expect(await sync.retrySync(), isFalse);
      expect(sync.syncState.pendingEvents, 5);
      backend.incompleteAcknowledgement = false;
      expect(await sync.retrySync(), isTrue);
      expect(sync.syncState.pendingEvents, 0);
      expect(backend.events, hasLength(5));
    },
  );

  test(
    'repeated sync requests share the same upload and avoid duplicates',
    () async {
      await startRound();
      backend.failEvents = true;
      await sync.uploadDemoEvent(
        studySessionController: study,
        pomodoroController: timer,
      );
      backend.failEvents = false;
      expect(await Future.wait([sync.retrySync(), sync.retrySync()]), [
        true,
        true,
      ]);
      expect(backend.events, hasLength(1));
      expect(backend.rounds, hasLength(1));
    },
  );

  test(
    'changing accounts cannot send the previous account records to a new user',
    () async {
      await startRound();
      auth.setSession(userId: 'other-user', email: 'other@example.test');
      expect(await sync.retrySync(), isFalse);
      expect(sync.syncState.phase, FocusSyncPhase.localOnly);
    },
  );

  test(
    'periodic synchronization retries failed completed rounds without a button',
    () async {
      sync.dispose();
      sync = FocusSyncController(
        authSession: auth,
        focusApi: FocusApi(backend.client),
        sessionSyncInterval: const Duration(milliseconds: 25),
        eventFlushInterval: const Duration(days: 1),
      );
      sync.start(studySessionController: study, pomodoroController: timer);
      await startRound();
      backend.failRoundUpdate = true;
      await completeRound();
      expect(sync.syncState.pendingRounds, 1);
      backend.failRoundUpdate = false;
      await backend.completedRoundSaved.future.timeout(
        const Duration(seconds: 2),
      );
      await Future<void>.delayed(Duration.zero);
      expect(sync.syncState.pendingRounds, 0);
      expect(backend.roundCreates, 1);
      expect(backend.rounds.values.single['status'], 'completed');
    },
  );
}

class _MemoryBackend {
  _MemoryBackend() {
    client = ApiClient(
      httpClient: MockClient(handle),
      baseUrl: 'http://phase3.test/api/v1',
    );
  }
  late final ApiClient client;
  bool offline = false;
  bool failRoundUpdate = false;
  bool failEvents = false;
  bool incompleteAcknowledgement = false;
  int roundCreates = 0;
  Completer<void>? roundGate;
  final roundRequested = Completer<void>();
  final completedRoundSaved = Completer<void>();
  Map<String, dynamic> session = {};
  final rounds = <String, Map<String, dynamic>>{};
  final events = <String>{};

  http.Response reply(Object data, [int status = 200]) => http.Response(
    jsonEncode(data),
    status,
    headers: {'content-type': 'application/json'},
  );

  Future<http.Response> handle(http.Request request) async {
    if (offline) return reply({'message': 'offline'}, 503);
    final path = request.url.path;
    final data = request.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;
    if (path.endsWith('/statistics')) {
      return reply({
        'today': {
          'focusSeconds': session['focusSeconds'] ?? 0,
          'completedRoundCount': rounds.values
              .where((r) => r['status'] == 'completed')
              .length,
        },
      });
    }
    if (path.endsWith('/focus-sessions')) {
      session = data;
      return reply({'sessionId': 'session-1'});
    }
    if (path.endsWith('/session-1')) {
      session = data;
      return reply({'sessionId': 'session-1'});
    }
    if (path.endsWith('/rounds')) {
      roundCreates++;
      if (!roundRequested.isCompleted) roundRequested.complete();
      await roundGate?.future;
      final id = data['clientRoundId'] as String;
      rounds.putIfAbsent(id, () => data);
      return reply({'roundId': id});
    }
    if (path.contains('/rounds/')) {
      if (failRoundUpdate) return reply({'message': 'round unavailable'}, 503);
      rounds[path.split('/').last] = data;
      if (data['status'] == 'completed' && !completedRoundSaved.isCompleted) {
        completedRoundSaved.complete();
      }
      return reply(data);
    }
    if (path.endsWith('/events/batch')) {
      if (failEvents) return reply({'message': 'events unavailable'}, 503);
      if (incompleteAcknowledgement) {
        return reply({'savedCount': 0, 'skippedDuplicateCount': 0});
      }
      var saved = 0;
      var duplicates = 0;
      for (final event in data['events'] as List) {
        events.add(event['clientEventId'] as String) ? saved++ : duplicates++;
      }
      return reply({'savedCount': saved, 'skippedDuplicateCount': duplicates});
    }
    throw StateError('Unexpected request: ${request.method} $path');
  }
}
