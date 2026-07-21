import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/focus_api.dart';
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

class FocusSyncController {
  FocusSyncController({
    required AuthSession authSession,
    FocusApi? focusApi,
    this.sessionSyncInterval = const Duration(seconds: 30),
    this.eventFlushInterval = const Duration(seconds: 20),
    this.eventBatchSize = 30,
  }) : _authSession = authSession,
       _focusApi = focusApi ?? FocusApi(ApiClient());

  final AuthSession _authSession;
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
  bool _isCreatingSession = false;
  bool _isSyncingSession = false;
  bool _isUploadingEvents = false;
  bool _isCreatingRound = false;
  bool _isUpdatingRound = false;
  bool _isClosed = false;

  String? get serverSessionId => _localSession?.serverSessionId;
  String? get currentServerRoundId => _currentRound?.serverRoundId;

  void start({
    required StudySessionController studySessionController,
    required PomodoroController pomodoroController,
  }) {
    if (_isClosed) return;
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
    final sessionId = await ensureRemoteSession(
      studySessionController: studySessionController,
      pomodoroController: pomodoroController,
    );
    if (sessionId == null || _isCreatingRound) return;

    _roundNumber += 1;
    _roundPausedAt = null;
    _roundPausedDuration = Duration.zero;
    final targetSeconds = pomodoroController.totalDuration.inSeconds;
    final round = FocusRoundSnapshot.start(
      sessionId: sessionId,
      roundNumber: _roundNumber,
      type: FocusRoundType.focus,
      targetSeconds: targetSeconds > 0 ? targetSeconds : 25 * 60,
    );
    _currentRound = round;

    _isCreatingRound = true;
    try {
      final response = await _focusApi.createMyRound(
        authSession: _authSession,
        sessionId: sessionId,
        round: round,
      );
      _currentRound = _copyRound(
        round,
        serverRoundId: _stringValue(response['roundId']),
      );
    } catch (error) {
      debugPrint('Focus round create failed: $error');
    } finally {
      _isCreatingRound = false;
    }
  }

  Future<void> updateCurrentRound({
    required FocusRoundStatus status,
    required StudySessionController studySessionController,
    required PomodoroController pomodoroController,
    FocusRoundEndReason? endReason,
    DateTime? endedAt,
  }) async {
    final current = _currentRound;
    final sessionId = serverSessionId;
    final roundId = current?.serverRoundId;
    if (current == null || sessionId == null || roundId == null) return;
    if (_isUpdatingRound) return;

    final snapshot = _copyRound(
      current,
      status: status,
      actualSeconds: _actualRoundSeconds(current, endedAt ?? DateTime.now()),
      pausedSeconds: _roundPausedDuration.inSeconds,
      endedAt: endedAt,
      endReason: endReason,
    );
    _currentRound = snapshot;

    _isUpdatingRound = true;
    try {
      await _focusApi.updateMyRound(
        authSession: _authSession,
        sessionId: sessionId,
        roundId: roundId,
        round: snapshot,
      );
    } catch (error) {
      debugPrint('Focus round update failed: $error');
    } finally {
      _isUpdatingRound = false;
    }

    if (endedAt != null) {
      _currentRound = null;
    }
    unawaited(
      syncSession(
        studySessionController: studySessionController,
        pomodoroController: pomodoroController,
      ),
    );
  }

  Future<String?> ensureRemoteSession({
    required StudySessionController studySessionController,
    required PomodoroController pomodoroController,
  }) async {
    if (!_authSession.isSignedIn || _authSession.userId == null) return null;
    final existingServerId = serverSessionId;
    if (existingServerId != null) return existingServerId;
    if (_isCreatingSession) return null;

    final session = _ensureLocalSession(
      studySessionController: studySessionController,
      pomodoroController: pomodoroController,
    );

    _isCreatingSession = true;
    try {
      final response = await _focusApi.createMySession(
        authSession: _authSession,
        session: session,
      );
      final remoteId = _stringValue(response['sessionId']);
      if (remoteId != null) {
        _localSession = _copySession(session, serverSessionId: remoteId);
      }
      return remoteId;
    } catch (error) {
      debugPrint('Focus session create failed: $error');
      return null;
    } finally {
      _isCreatingSession = false;
    }
  }

  Future<void> syncSession({
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
    if (sessionId == null || _isSyncingSession) return;

    _isSyncingSession = true;
    try {
      final snapshot = _buildSessionSnapshot(
        studySessionController: studySessionController,
        pomodoroController: pomodoroController,
        status: status,
        endReason: endReason,
        endedAt: endedAt,
      );
      await _focusApi.updateMySession(
        authSession: _authSession,
        sessionId: sessionId,
        session: snapshot,
      );
      _localSession = snapshot;
    } catch (error) {
      debugPrint('Focus session sync failed: $error');
    } finally {
      _isSyncingSession = false;
    }
  }

  Future<FocusEventUploadResult> flushEvents({
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
    if (_isUploadingEvents) {
      return const FocusEventUploadResult.failure(
        message: 'Event upload is already in progress.',
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

    _isUploadingEvents = true;
    try {
      final response = await _focusApi.uploadMyEvents(
        authSession: _authSession,
        sessionId: sessionId,
        events: events,
      );
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
      _isUploadingEvents = false;
    }
  }

  Future<void> flushNow({
    required StudySessionController studySessionController,
    required PomodoroController pomodoroController,
  }) async {
    await flushEvents(
      studySessionController: studySessionController,
      pomodoroController: pomodoroController,
    );
    await syncSession(
      studySessionController: studySessionController,
      pomodoroController: pomodoroController,
    );
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
        syncSession(
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
    FocusRoundStatus? status,
    int? actualSeconds,
    int? pausedSeconds,
    DateTime? endedAt,
    FocusRoundEndReason? endReason,
  }) {
    return FocusRoundSnapshot(
      clientRoundId: source.clientRoundId,
      serverRoundId: serverRoundId ?? source.serverRoundId,
      sessionId: source.sessionId,
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

  String? _stringValue(Object? value) => value?.toString();

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
