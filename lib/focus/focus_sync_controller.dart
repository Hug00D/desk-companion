import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/focus_api.dart';
import '../api/user_facing_error.dart';
import 'focus_sync_state.dart';
import '../auth/auth_session.dart';
import '../events/companion_event.dart';
import '../events/companion_event_buffer.dart';
import '../vision/vision_event.dart';
import '../vision/vision_event_tracker.dart';
import '../voice/voice_command.dart';
import '../voice/voice_interaction_controller.dart';
import '../voice/voice_result.dart';
import 'focus_round.dart';
import 'pomodoro_controller.dart';
import 'study_session.dart';
import 'study_session_controller.dart';

class FocusSyncController extends ChangeNotifier {
  /// The home route owns the active controller; other routes may retry it.
  static FocusSyncController? active;
  FocusSyncController({
    required AuthSession authSession,
    FocusApi? focusApi,
    this.sessionSyncInterval = const Duration(seconds: 30),
    this.eventFlushInterval = const Duration(seconds: 20),
    this.eventBatchSize = 30,
  }) : _authSession = authSession,
       _ownerUserId = authSession.userId,
       _focusApi = focusApi ?? FocusApi(ApiClient());

  final AuthSession _authSession;
  final String? _ownerUserId;
  final FocusApi _focusApi;
  final CompanionEventBuffer _eventBuffer = CompanionEventBuffer();
  final Duration sessionSyncInterval;
  final Duration eventFlushInterval;
  final int eventBatchSize;

  Timer? _sessionSyncTimer;
  Timer? _eventFlushTimer;
  StudySessionSnapshot? _localSession;
  FocusRoundSnapshot? _currentRound;
  DateTime? _roundPausedAt;
  Duration _roundPausedDuration = Duration.zero;
  int _revision = 0;
  int _roundNumber = 0;
  bool _isClosed = false;
  bool _disposed = false;
  int _requestsInFlight = 0;
  final Map<String, String> _errors = {};
  final Map<String, FocusRoundSnapshot> _pendingRounds = {};
  Future<String?>? _sessionCreation;
  Future<void>? _sessionWrite;
  Future<void>? _roundWrite;
  Future<FocusEventUploadResult>? _eventUpload;
  Future<void>? _flushInFlight;
  StudySessionController? _studyController;
  PomodoroController? _timerController;
  DateTime? _lastSyncedAt;

  bool get _canSync =>
      _authSession.isSignedIn && _authSession.userId == _ownerUserId;
  FocusSyncState get syncState => FocusSyncState(
    phase: !_canSync
        ? FocusSyncPhase.localOnly
        : _requestsInFlight > 0 || _flushInFlight != null
        ? FocusSyncPhase.syncing
        : _errors.isNotEmpty
        ? FocusSyncPhase.failed
        : _eventBuffer.length > 0 ||
              _pendingRounds.isNotEmpty ||
              _lastSyncedAt == null
        ? FocusSyncPhase.pending
        : FocusSyncPhase.synced,
    pendingEvents: _eventBuffer.length,
    pendingRounds: _pendingRounds.length,
    lastSyncedAt: _lastSyncedAt,
    message: _errors.isEmpty ? null : _errors.values.first,
  );

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  Future<T> _request<T>(String key, Future<T> Function() action) async {
    if (!_canSync) throw StateError('Account changed during sync');
    _requestsInFlight++;
    _emit();
    try {
      final result = await action();
      _errors.remove(key);
      return result;
    } catch (error) {
      _errors[key] = userFacingError(error);
      rethrow;
    } finally {
      _requestsInFlight--;
      _emit();
    }
  }

  Future<bool> retrySync() async {
    final study = _studyController;
    final timer = _timerController;
    if (!_canSync || study == null || timer == null || _isClosed) return false;
    await flushNow(studySessionController: study, pomodoroController: timer);
    return _errors.isEmpty && _eventBuffer.isEmpty && _pendingRounds.isEmpty;
  }

  @override
  void dispose() {
    _disposed = true;
    _sessionSyncTimer?.cancel();
    _eventFlushTimer?.cancel();
    if (identical(active, this)) active = null;
    super.dispose();
  }

  String? get serverSessionId => _localSession?.serverSessionId;
  String? get currentServerRoundId => _currentRound?.serverRoundId;
  String? get currentClientRoundId => _currentRound?.clientRoundId;
  DateTime? get currentRoundStartedAt => _currentRound?.startedAt;

  void start({
    required StudySessionController studySessionController,
    required PomodoroController pomodoroController,
  }) {
    if (_isClosed) return;
    _studyController = studySessionController;
    _timerController = pomodoroController;
    studySessionController.ensureStarted();
    _ensureLocalSession(
      studySessionController: studySessionController,
      pomodoroController: pomodoroController,
    );
    unawaited(
      ensureRemoteSession(
        studySessionController: studySessionController,
        pomodoroController: pomodoroController,
      ),
    );
    _startTimers(
      studySessionController: studySessionController,
      pomodoroController: pomodoroController,
    );
  }

  void recordVisionTrackingResult(
    VisionEventTrackingResult trackingResult, {
    required StudySessionController studySessionController,
    required PomodoroController pomodoroController,
  }) {
    if (!trackingResult.shouldPersist) return;

    final session = _ensureLocalSession(
      studySessionController: studySessionController,
      pomodoroController: pomodoroController,
    );
    final visionEvent = trackingResult.event;
    final event = CompanionEvent.create(
      sessionId: session.serverSessionId ?? session.clientSessionId,
      roundId: _currentRound?.serverRoundId,
      source: CompanionEventSource.vision,
      eventType: visionEvent.type.storageValue,
      occurredAt: visionEvent.timestamp,
      severity: _visionSeverity(visionEvent.severity),
      duration: trackingResult.consecutiveDuration,
      confidenceScore: visionEvent.confidenceScore,
      actionTriggered: visionEvent.actionTriggered,
      signals: visionEvent.toSignalsJson(),
    );
    _eventBuffer.add(event);
    debugPrint(
      'Queued vision event: ${event.eventType}, '
      'pending=${_eventBuffer.length}, '
      'session=${event.sessionId}',
    );
    _flushIfNeeded(
      studySessionController: studySessionController,
      pomodoroController: pomodoroController,
    );
  }

  void recordVoiceInteraction(
    VoiceInteraction interaction, {
    required StudySessionController studySessionController,
    required PomodoroController pomodoroController,
    String? actionLabel,
  }) {
    final session = _ensureLocalSession(
      studySessionController: studySessionController,
      pomodoroController: pomodoroController,
    );
    final command = interaction.command;
    _eventBuffer.add(
      CompanionEvent.create(
        sessionId: session.serverSessionId ?? session.clientSessionId,
        roundId: _currentRound?.serverRoundId,
        source: CompanionEventSource.voice,
        eventType: _voiceEventType(command),
        occurredAt: _voiceOccurredAt(interaction.result),
        severity: _voiceSeverity(command),
        confidenceScore:
            command.confidence ?? interaction.result.bestConfidence,
        actionTriggered: actionLabel,
        outcome: command.isActionable
            ? CompanionEventOutcome.applied
            : CompanionEventOutcome.rejected,
        signals: <String, dynamic>{
          'recognition': _voiceRecognitionJson(interaction.result),
          'command': _voiceCommandJson(command),
        },
      ),
    );
    _flushIfNeeded(
      studySessionController: studySessionController,
      pomodoroController: pomodoroController,
    );
  }

  void recordPomodoroAction(
    VoiceCommand command, {
    required StudySessionController studySessionController,
    required PomodoroController pomodoroController,
    required PomodoroStatus previousStatus,
    String? actionLabel,
  }) {
    if (actionLabel == null) return;

    switch (command.type) {
      case VoiceCommandType.startPomodoro:
        if (actionLabel == 'start_pomodoro') {
          unawaited(
            startFocusRound(
              studySessionController: studySessionController,
              pomodoroController: pomodoroController,
            ),
          );
        }
        break;
      case VoiceCommandType.pausePomodoro:
        if (actionLabel == 'pause_pomodoro') {
          _markRoundPaused();
          unawaited(
            updateCurrentRound(
              status: FocusRoundStatus.paused,
              studySessionController: studySessionController,
              pomodoroController: pomodoroController,
            ),
          );
        }
        break;
      case VoiceCommandType.resumePomodoro:
        if (actionLabel == 'resume_pomodoro') {
          _markRoundResumed();
          unawaited(
            updateCurrentRound(
              status: FocusRoundStatus.active,
              studySessionController: studySessionController,
              pomodoroController: pomodoroController,
            ),
          );
        }
        break;
      case VoiceCommandType.stopPomodoro:
        if (actionLabel == 'stop_pomodoro') {
          _markRoundResumed();
          unawaited(
            updateCurrentRound(
              status: FocusRoundStatus.stopped,
              endReason: FocusRoundEndReason.userStopped,
              endedAt: DateTime.now(),
              studySessionController: studySessionController,
              pomodoroController: pomodoroController,
            ),
          );
        }
        break;
      case VoiceCommandType.requestBreak:
        if (previousStatus == PomodoroStatus.running &&
            actionLabel == 'start_eye_break') {
          _markRoundPaused();
          unawaited(
            updateCurrentRound(
              status: FocusRoundStatus.paused,
              studySessionController: studySessionController,
              pomodoroController: pomodoroController,
            ),
          );
        }
        break;
      case VoiceCommandType.requestFocusSummary:
      case VoiceCommandType.requestTimerStatus:
      case VoiceCommandType.reportTired:
      case VoiceCommandType.reportDistracted:
      case VoiceCommandType.confirmStartPomodoro:
      case VoiceCommandType.unknown:
      case VoiceCommandType.ignored:
        break;
    }

    _queueTimerEvent(
      actionLabel,
      studySessionController: studySessionController,
      pomodoroController: pomodoroController,
      command: command,
    );
  }

  void recordPomodoroCompleted({
    required StudySessionController studySessionController,
    required PomodoroController pomodoroController,
  }) {
    _markRoundResumed();
    _queueTimerEvent(
      'pomodoro_completed',
      studySessionController: studySessionController,
      pomodoroController: pomodoroController,
    );
    unawaited(
      updateCurrentRound(
        status: FocusRoundStatus.completed,
        endReason: FocusRoundEndReason.completed,
        endedAt: DateTime.now(),
        studySessionController: studySessionController,
        pomodoroController: pomodoroController,
      ),
    );
  }

  Future<FocusEventUploadResult> uploadDemoEvent({
    required StudySessionController studySessionController,
    required PomodoroController pomodoroController,
  }) async {
    final sessionId = await ensureRemoteSession(
      studySessionController: studySessionController,
      pomodoroController: pomodoroController,
    );
    if (sessionId == null) {
      return const FocusEventUploadResult.failure(
        message: 'Remote focus session is not ready.',
      );
    }

    _eventBuffer.add(
      CompanionEvent.create(
        sessionId: sessionId,
        roundId: _currentRound?.serverRoundId,
        source: CompanionEventSource.system,
        eventType: 'system.demo_event_upload',
        severity: CompanionEventSeverity.info,
        actionTriggered: 'event_upload_demo',
        outcome: CompanionEventOutcome.shown,
        signals: <String, dynamic>{
          'demo': true,
          'pomodoroStatus': pomodoroController.status.name,
          'remainingSeconds': pomodoroController.remaining.inSeconds,
          'pendingBeforeUpload': _eventBuffer.length,
        },
      ),
    );

    return flushEvents(
      studySessionController: studySessionController,
      pomodoroController: pomodoroController,
    );
  }

  Future<void> startFocusRound({
    required StudySessionController studySessionController,
    required PomodoroController pomodoroController,
  }) async {
    final session = _ensureLocalSession(
      studySessionController: studySessionController,
      pomodoroController: pomodoroController,
    );
    _roundNumber++;
    _roundPausedAt = null;
    _roundPausedDuration = Duration.zero;
    final round = FocusRoundSnapshot.start(
      sessionId: session.serverSessionId ?? session.clientSessionId,
      roundNumber: _roundNumber,
      type: FocusRoundType.focus,
      targetSeconds: pomodoroController.totalDuration.inSeconds > 0
          ? pomodoroController.totalDuration.inSeconds
          : 25 * 60,
    );
    _currentRound = round;
    _pendingRounds[round.clientRoundId] = round;
    _emit();
    await _flushRounds(studySessionController, pomodoroController);
  }

  Future<void> updateCurrentRound({
    required FocusRoundStatus status,
    required StudySessionController studySessionController,
    required PomodoroController pomodoroController,
    FocusRoundEndReason? endReason,
    DateTime? endedAt,
  }) async {
    final current = _currentRound;
    if (current == null) return;
    if (status == FocusRoundStatus.paused) {
      _markRoundPaused();
    } else {
      _markRoundResumed();
    }
    final snapshot = _copyRound(
      current,
      status: status,
      actualSeconds: _actualRoundSeconds(current, endedAt ?? DateTime.now()),
      pausedSeconds: _roundPausedDuration.inSeconds,
      endedAt: endedAt,
      endReason: endReason,
    );
    _pendingRounds[snapshot.clientRoundId] = snapshot;
    _currentRound = endedAt == null ? snapshot : null;
    _emit();
    await _flushRounds(studySessionController, pomodoroController);
    await syncSession(
      studySessionController: studySessionController,
      pomodoroController: pomodoroController,
    );
  }

  Future<void> _flushRounds(
    StudySessionController study,
    PomodoroController timer,
  ) {
    return _roundWrite ??= _performRoundSync(study, timer).whenComplete(() {
      _roundWrite = null;
      _emit();
    });
  }

  Future<void> _performRoundSync(
    StudySessionController study,
    PomodoroController timer,
  ) async {
    if (_pendingRounds.isEmpty) return;
    final sessionId = await ensureRemoteSession(
      studySessionController: study,
      pomodoroController: timer,
    );
    if (sessionId == null) return;
    while (_pendingRounds.isNotEmpty) {
      var snapshot = _pendingRounds.values.first;
      final key = snapshot.clientRoundId;
      try {
        if (snapshot.serverRoundId == null) {
          final response = await _request(
            'round:$key',
            () => _focusApi.createMyRound(
              authSession: _authSession,
              sessionId: sessionId,
              round: _copyRound(snapshot, sessionId: sessionId),
            ),
          );
          final roundId = _stringValue(response['roundId']);
          if (roundId == null) throw const FormatException('Missing roundId');
          // Completion may have arrived while the create request was in flight.
          snapshot = _copyRound(
            _pendingRounds[key] ?? snapshot,
            serverRoundId: roundId,
            sessionId: sessionId,
          );
          _pendingRounds[key] = snapshot;
          if (_currentRound?.clientRoundId == key) _currentRound = snapshot;
        }
        final sent = snapshot;
        await _request(
          'round:$key',
          () => _focusApi.updateMyRound(
            authSession: _authSession,
            sessionId: sessionId,
            roundId: sent.serverRoundId!,
            round: sent,
          ),
        );
        if (identical(_pendingRounds[key], sent)) _pendingRounds.remove(key);
      } catch (error) {
        _errors['round:$key'] = userFacingError(error);
        debugPrint('Focus round sync deferred: $error');
        return;
      } finally {
        _emit();
      }
    }
  }

  Future<String?> ensureRemoteSession({
    required StudySessionController studySessionController,
    required PomodoroController pomodoroController,
  }) {
    if (!_canSync) return Future.value(null);
    if (serverSessionId != null) return Future.value(serverSessionId);
    return _sessionCreation ??= _createRemoteSession(
      studySessionController,
      pomodoroController,
    ).whenComplete(() => _sessionCreation = null);
  }

  Future<String?> _createRemoteSession(
    StudySessionController study,
    PomodoroController timer,
  ) async {
    final session = _ensureLocalSession(
      studySessionController: study,
      pomodoroController: timer,
    );
    try {
      final response = await _request(
        'session:create',
        () => _focusApi.createMySession(
          authSession: _authSession,
          session: session,
        ),
      );
      final remoteId = _stringValue(response['sessionId']);
      if (remoteId == null) throw const FormatException('Missing sessionId');
      _localSession = _copySession(session, serverSessionId: remoteId);
      return remoteId;
    } catch (error) {
      _errors['session:create'] = userFacingError(error);
      debugPrint('Focus session create failed: $error');
      return null;
    } finally {
      _emit();
    }
  }

  Future<void> syncSession({
    required StudySessionController studySessionController,
    required PomodoroController pomodoroController,
    StudySessionStatus status = StudySessionStatus.active,
    StudySessionEndReason? endReason,
    DateTime? endedAt,
  }) {
    final write = (_sessionWrite ?? Future<void>.value()).then(
      (_) => _syncSessionOnce(
        studySessionController: studySessionController,
        pomodoroController: pomodoroController,
        status: status,
        endReason: endReason,
        endedAt: endedAt,
      ),
    );
    _sessionWrite = write;
    return write;
  }

  Future<void> _syncSessionOnce({
    required StudySessionController studySessionController,
    required PomodoroController pomodoroController,
    StudySessionStatus status = StudySessionStatus.active,
    StudySessionEndReason? endReason,
    DateTime? endedAt,
  }) async {
    final sessionId = await ensureRemoteSession(
      studySessionController: studySessionController,
      pomodoroController: pomodoroController,
    );
    if (sessionId == null) return;
    try {
      final snapshot = _buildSessionSnapshot(
        studySessionController: studySessionController,
        pomodoroController: pomodoroController,
        status: status,
        endReason: endReason,
        endedAt: endedAt,
      );
      await _request(
        'session:update',
        () => _focusApi.updateMySession(
          authSession: _authSession,
          sessionId: sessionId,
          session: snapshot,
        ),
      );
      _localSession = snapshot;
      if (_errors.isEmpty && _eventBuffer.isEmpty && _pendingRounds.isEmpty) {
        _lastSyncedAt = DateTime.now();
      }
    } catch (error) {
      debugPrint('Focus session sync failed: $error');
    }
  }

  Future<FocusEventUploadResult> flushEvents({
    required StudySessionController studySessionController,
    required PomodoroController pomodoroController,
  }) {
    return _eventUpload ??=
        _flushEventsOnce(
          studySessionController: studySessionController,
          pomodoroController: pomodoroController,
        ).whenComplete(() {
          _eventUpload = null;
          _emit();
        });
  }

  Future<FocusEventUploadResult> _flushEventsOnce({
    required StudySessionController studySessionController,
    required PomodoroController pomodoroController,
  }) async {
    if (_eventBuffer.isEmpty) {
      return const FocusEventUploadResult.success(
        attemptedCount: 0,
        savedCount: 0,
        skippedDuplicateCount: 0,
      );
    }
    final sessionId = await ensureRemoteSession(
      studySessionController: studySessionController,
      pomodoroController: pomodoroController,
    );
    if (sessionId == null) {
      return const FocusEventUploadResult.failure(
        message: 'Remote focus session is not ready.',
      );
    }

    final events = _eventBuffer.takeBatch(limit: eventBatchSize);
    if (events.isEmpty) {
      return const FocusEventUploadResult.success(
        attemptedCount: 0,
        savedCount: 0,
        skippedDuplicateCount: 0,
      );
    }

    try {
      final response = await _request(
        'events',
        () => _focusApi.uploadMyEvents(
          authSession: _authSession,
          sessionId: sessionId,
          events: events,
        ),
      );
      final acknowledged =
          _intValue(response['savedCount']) +
          _intValue(response['skippedDuplicateCount']);
      if (acknowledged != events.length) {
        throw const FormatException('Incomplete event acknowledgement');
      }
      _eventBuffer.markUploaded(events.map((event) => event.clientEventId));
      debugPrint(
        'Uploaded focus events: '
        'attempted=${events.length}, '
        'saved=${_intValue(response['savedCount'])}, '
        'types=${events.map((event) => event.eventType).join(', ')}',
      );
      return FocusEventUploadResult.success(
        sessionId: sessionId,
        attemptedCount: events.length,
        savedCount: _intValue(response['savedCount']),
        skippedDuplicateCount: _intValue(response['skippedDuplicateCount']),
        eventTypes: events.map((event) => event.eventType).toList(),
      );
    } catch (error) {
      _errors['events'] = userFacingError(error);
      debugPrint(
        'Focus events upload failed: $error, '
        'types=${events.map((event) => event.eventType).join(', ')}',
      );
      return FocusEventUploadResult.failure(
        sessionId: sessionId,
        attemptedCount: events.length,
        message: error.toString(),
        eventTypes: events.map((event) => event.eventType).toList(),
      );
    } finally {
      _emit();
    }
  }

  Future<void> flushNow({
    required StudySessionController studySessionController,
    required PomodoroController pomodoroController,
  }) {
    return _flushInFlight ??=
        _flushAll(studySessionController, pomodoroController).whenComplete(() {
          _flushInFlight = null;
          _emit();
        });
  }

  Future<void> _flushAll(
    StudySessionController study,
    PomodoroController timer,
  ) async {
    await _flushRounds(study, timer);
    // Drain the backlog that existed when retry began, without blocking
    // indefinitely if vision continues producing new events.
    var remaining = _eventBuffer.length;
    while (remaining > 0) {
      final result = await flushEvents(
        studySessionController: study,
        pomodoroController: timer,
      );
      if (!result.success || result.attemptedCount == 0) break;
      remaining -= result.attemptedCount;
    }
    await syncSession(studySessionController: study, pomodoroController: timer);
    if (_canSync &&
        _errors.isEmpty &&
        _eventBuffer.isEmpty &&
        _pendingRounds.isEmpty &&
        serverSessionId != null) {
      _lastSyncedAt = DateTime.now();
    }
    _emit();
  }

  Future<void> close({
    required StudySessionController studySessionController,
    required PomodoroController pomodoroController,
    StudySessionEndReason endReason = StudySessionEndReason.appClosed,
  }) async {
    _isClosed = true;
    _sessionSyncTimer?.cancel();
    _eventFlushTimer?.cancel();
    await flushEvents(
      studySessionController: studySessionController,
      pomodoroController: pomodoroController,
    );
    await syncSession(
      studySessionController: studySessionController,
      pomodoroController: pomodoroController,
      status: StudySessionStatus.stopped,
      endReason: endReason,
      endedAt: DateTime.now(),
    );
  }

  void _startTimers({
    required StudySessionController studySessionController,
    required PomodoroController pomodoroController,
  }) {
    _sessionSyncTimer ??= Timer.periodic(sessionSyncInterval, (_) {
      unawaited(
        flushNow(
          studySessionController: studySessionController,
          pomodoroController: pomodoroController,
        ),
      );
    });
    _eventFlushTimer ??= Timer.periodic(eventFlushInterval, (_) {
      unawaited(
        flushEvents(
          studySessionController: studySessionController,
          pomodoroController: pomodoroController,
        ),
      );
    });
  }

  void _flushIfNeeded({
    required StudySessionController studySessionController,
    required PomodoroController pomodoroController,
  }) {
    _emit();
    if (_eventBuffer.length < eventBatchSize) return;
    unawaited(
      flushEvents(
        studySessionController: studySessionController,
        pomodoroController: pomodoroController,
      ),
    );
  }

  StudySessionSnapshot _ensureLocalSession({
    required StudySessionController studySessionController,
    required PomodoroController pomodoroController,
  }) {
    final existing = _localSession;
    if (existing != null) return existing;
    studySessionController.ensureStarted();
    final session = studySessionController.toSnapshot(
      clientSessionId: generateClientUuid(),
      timezone: DateTime.now().timeZoneName,
      targetSeconds: pomodoroController.totalDuration.inSeconds > 0
          ? pomodoroController.totalDuration.inSeconds
          : null,
      config: const <String, dynamic>{
        'source': 'flutter',
        'mode': 'camera_monitoring',
      },
    );
    _localSession = session;
    return session;
  }

  StudySessionSnapshot _buildSessionSnapshot({
    required StudySessionController studySessionController,
    required PomodoroController pomodoroController,
    StudySessionStatus status = StudySessionStatus.active,
    StudySessionEndReason? endReason,
    DateTime? endedAt,
  }) {
    final local = _ensureLocalSession(
      studySessionController: studySessionController,
      pomodoroController: pomodoroController,
    );
    _revision += 1;
    return studySessionController.toSnapshot(
      clientSessionId: local.clientSessionId,
      serverSessionId: local.serverSessionId,
      timezone: local.timezone,
      status: status,
      endReason: endReason,
      endedAt: endedAt,
      targetSeconds: pomodoroController.totalDuration.inSeconds > 0
          ? pomodoroController.totalDuration.inSeconds
          : local.targetSeconds,
      pausedSeconds: _roundPausedDuration.inSeconds,
      config: local.config,
      revision: _revision,
    );
  }

  void _queueTimerEvent(
    String eventType, {
    required StudySessionController studySessionController,
    required PomodoroController pomodoroController,
    VoiceCommand? command,
  }) {
    final session = _ensureLocalSession(
      studySessionController: studySessionController,
      pomodoroController: pomodoroController,
    );
    _eventBuffer.add(
      CompanionEvent.create(
        sessionId: session.serverSessionId ?? session.clientSessionId,
        roundId: _currentRound?.serverRoundId,
        source: CompanionEventSource.timer,
        eventType: 'timer.$eventType',
        actionTriggered: eventType,
        outcome: CompanionEventOutcome.applied,
        signals: <String, dynamic>{
          'pomodoroStatus': pomodoroController.status.name,
          'remainingSeconds': pomodoroController.remaining.inSeconds,
          'totalSeconds': pomodoroController.totalDuration.inSeconds,
          if (command != null) 'voiceCommand': _voiceCommandJson(command),
        },
      ),
    );
    _flushIfNeeded(
      studySessionController: studySessionController,
      pomodoroController: pomodoroController,
    );
  }

  void _markRoundPaused() {
    _roundPausedAt ??= DateTime.now();
  }

  void _markRoundResumed() {
    final pausedAt = _roundPausedAt;
    if (pausedAt == null) return;
    final delta = DateTime.now().difference(pausedAt);
    if (delta > Duration.zero) {
      _roundPausedDuration += delta;
    }
    _roundPausedAt = null;
  }

  int _actualRoundSeconds(FocusRoundSnapshot round, DateTime now) {
    final seconds = now.difference(round.startedAt).inSeconds;
    return seconds < 0 ? 0 : seconds;
  }

  StudySessionSnapshot _copySession(
    StudySessionSnapshot source, {
    String? serverSessionId,
  }) {
    return StudySessionSnapshot(
      clientSessionId: source.clientSessionId,
      serverSessionId: serverSessionId ?? source.serverSessionId,
      startedAt: source.startedAt,
      endedAt: source.endedAt,
      status: source.status,
      endReason: source.endReason,
      mode: source.mode,
      timezone: source.timezone,
      targetSeconds: source.targetSeconds,
      monitoredSeconds: source.monitoredSeconds,
      focusSeconds: source.focusSeconds,
      attentionSeconds: source.attentionSeconds,
      distractedSeconds: source.distractedSeconds,
      fatigueSeconds: source.fatigueSeconds,
      drowsySeconds: source.drowsySeconds,
      postureDownSeconds: source.postureDownSeconds,
      awaySeconds: source.awaySeconds,
      pausedSeconds: source.pausedSeconds,
      breakSeconds: source.breakSeconds,
      reminderShownCount: source.reminderShownCount,
      summary: source.summary,
      config: source.config,
      revision: source.revision,
      schemaVersion: source.schemaVersion,
    );
  }

  FocusRoundSnapshot _copyRound(
    FocusRoundSnapshot source, {
    String? serverRoundId,
    String? sessionId,
    FocusRoundStatus? status,
    int? actualSeconds,
    int? pausedSeconds,
    DateTime? endedAt,
    FocusRoundEndReason? endReason,
  }) {
    return FocusRoundSnapshot(
      clientRoundId: source.clientRoundId,
      serverRoundId: serverRoundId ?? source.serverRoundId,
      sessionId: sessionId ?? source.sessionId,
      roundNumber: source.roundNumber,
      type: source.type,
      status: status ?? source.status,
      targetSeconds: source.targetSeconds,
      actualSeconds: actualSeconds ?? source.actualSeconds,
      pausedSeconds: pausedSeconds ?? source.pausedSeconds,
      startedAt: source.startedAt,
      endedAt: endedAt ?? source.endedAt,
      endReason: endReason ?? source.endReason,
      schemaVersion: source.schemaVersion,
    );
  }

  CompanionEventSeverity _visionSeverity(VisionEventSeverity severity) {
    switch (severity) {
      case VisionEventSeverity.info:
        return CompanionEventSeverity.info;
      case VisionEventSeverity.attention:
        return CompanionEventSeverity.attention;
      case VisionEventSeverity.warning:
        return CompanionEventSeverity.warning;
    }
  }

  CompanionEventSeverity _voiceSeverity(VoiceCommand command) {
    switch (command.type) {
      case VoiceCommandType.unknown:
      case VoiceCommandType.confirmStartPomodoro:
        return CompanionEventSeverity.attention;
      case VoiceCommandType.ignored:
        return CompanionEventSeverity.info;
      case VoiceCommandType.reportTired:
      case VoiceCommandType.reportDistracted:
      case VoiceCommandType.requestBreak:
        return CompanionEventSeverity.warning;
      case VoiceCommandType.startPomodoro:
      case VoiceCommandType.pausePomodoro:
      case VoiceCommandType.resumePomodoro:
      case VoiceCommandType.stopPomodoro:
      case VoiceCommandType.requestFocusSummary:
      case VoiceCommandType.requestTimerStatus:
        return CompanionEventSeverity.info;
    }
  }

  String _voiceEventType(VoiceCommand command) {
    if (command.type == VoiceCommandType.unknown) {
      return 'voice.command_unknown';
    }
    if (command.type == VoiceCommandType.ignored) {
      return 'voice.command_ignored';
    }
    return 'voice.${command.type.name}';
  }

  DateTime _voiceOccurredAt(VoiceRecognitionResult result) {
    if (result.timestampMs <= 0) return DateTime.now();
    return DateTime.fromMillisecondsSinceEpoch(result.timestampMs);
  }

  Map<String, dynamic> _voiceRecognitionJson(VoiceRecognitionResult result) {
    return <String, dynamic>{
      'sessionId': result.sessionId,
      'caseId': result.caseId,
      'eventType': result.eventType.name,
      'timestampMs': result.timestampMs,
      'isFinal': result.isFinal,
      'bestText': result.bestText,
      'bestConfidence': result.bestConfidence,
      if (result.language != null)
        'language': <String, dynamic>{
          'tag': result.language!.tag,
          'confidenceLevel': result.language!.confidenceLevel,
          'alternatives': result.language!.alternatives,
        },
      if (result.error != null)
        'error': <String, dynamic>{
          'code': result.error!.code,
          'message': result.error!.message,
        },
    };
  }

  Map<String, dynamic> _voiceCommandJson(VoiceCommand command) {
    return <String, dynamic>{
      'type': command.type.name,
      'sourceText': command.sourceText,
      'confidence': command.confidence,
      'durationMinutes': command.durationMinutes,
      'reason': command.reason,
      'isActionable': command.isActionable,
    };
  }

  String? _stringValue(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }
}

class FocusEventUploadResult {
  const FocusEventUploadResult._({
    required this.success,
    required this.attemptedCount,
    required this.savedCount,
    required this.skippedDuplicateCount,
    required this.eventTypes,
    this.sessionId,
    this.message,
  });

  const FocusEventUploadResult.success({
    required int attemptedCount,
    required int savedCount,
    required int skippedDuplicateCount,
    String? sessionId,
    List<String> eventTypes = const <String>[],
  }) : this._(
         success: true,
         sessionId: sessionId,
         attemptedCount: attemptedCount,
         savedCount: savedCount,
         skippedDuplicateCount: skippedDuplicateCount,
         eventTypes: eventTypes,
       );

  const FocusEventUploadResult.failure({
    required String message,
    String? sessionId,
    int attemptedCount = 0,
    List<String> eventTypes = const <String>[],
  }) : this._(
         success: false,
         sessionId: sessionId,
         attemptedCount: attemptedCount,
         savedCount: 0,
         skippedDuplicateCount: 0,
         eventTypes: eventTypes,
         message: message,
       );

  final bool success;
  final String? sessionId;
  final int attemptedCount;
  final int savedCount;
  final int skippedDuplicateCount;
  final List<String> eventTypes;
  final String? message;
}
