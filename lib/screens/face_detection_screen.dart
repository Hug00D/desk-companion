import 'dart:async';
import 'dart:io' as io;
import 'dart:ui' show ImageFilter;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as video_thumbnail;

import '../auth/auth_session.dart';
import '../ai/assistant_interaction_controller.dart';
import '../ai/pending_action_controller.dart';
import '../api/api_client.dart';
import '../api/assistant_api.dart';
import '../companion/companion_controller.dart';
import '../companion/character_reaction.dart';
import '../companion/companion_response_builder.dart';
import '../focus/focus_session_monitor.dart';
import '../focus/focus_round.dart';
import '../focus/pomodoro_action_dispatcher.dart';
import '../focus/pomodoro_controller.dart';
import '../focus/focus_sync_controller.dart';
import '../focus/study_session_controller.dart';
import '../vision/companion_state_evaluator.dart';
import '../vision/vision_channel.dart';
import '../vision/vision_event.dart';
import '../vision/vision_event_tracker.dart';
import '../vision/vision_result.dart';
import '../voice/voice_command.dart';
import '../voice/device_speech_recognition_service.dart';
import '../voice/mock_voice_result_loader.dart';
import '../voice/voice_interaction_controller.dart';
import '../voice/voice_result.dart';
import '../voice/voice_service_client.dart';
import '../widgets/glass_bottom_nav_bar.dart';
import '../widgets/live2d_character_background.dart';
import 'profile_detail_screen.dart';
import 'profile_hub_screen.dart';
import 'statistics_screen.dart';
import 'tasks_screen.dart';

class _ReminderClip {
  const _ReminderClip(this.assetPath, this.message);

  final String assetPath;
  final String message;
}

class FaceDetectionScreen extends StatefulWidget {
  const FaceDetectionScreen({super.key});

  @override
  State<FaceDetectionScreen> createState() => _FaceDetectionScreenState();
}

class _FaceDetectionScreenState extends State<FaceDetectionScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  VideoPlayerController? _fallbackVideoController;
  VoidCallback? _fallbackVideoPositionListener;
  StreamSubscription<VisionResult>? _nativeVisionSubscription;

  Timer? _detectionTimer;
  Timer? _userStatusCollapseTimer;
  Timer? _idleBubbleTimer;
  Timer? _idleBubbleHideTimer;
  Timer? _focusPauseAutoDismissTimer;
  StreamSubscription<PlayerState>? _voicePlayerStateSubscription;
  late final AnimationController _breathingController;
  bool _isProcessing = false;
  bool _isCameraInitializing = true;
  bool _isUsingNativeCamera = false;
  bool _isUsingFallbackVideo = false;
  bool _isVoiceDemoLoading = false;
  String _status = "等待辨識...";
  String? _cameraErrorMessage;
  String? _fallbackVideoPath;
  final VisionChannel _visionChannel = const VisionChannel();
  final CompanionController _companionController = CompanionController();
  final CompanionResponseBuilder _responseBuilder =
      const CompanionResponseBuilder();
  final MockVoiceResultLoader _mockVoiceResultLoader =
      const MockVoiceResultLoader(assetPath: 'assets/mock/voice_intents.json');
  final VoiceInteractionController _voiceInteractionController =
      const VoiceInteractionController();
  final DeviceSpeechRecognitionService _deviceSpeechRecognitionService =
      DeviceSpeechRecognitionService();
  final TextEditingController _assistantTextController =
      TextEditingController();
  final PendingActionController _pendingActionController =
      PendingActionController();
  late final AssistantInteractionController _assistantInteractionController;
  final VoiceServiceClient _voiceServiceClient = VoiceServiceClient();
  final AudioPlayer _voiceAudioPlayer = AudioPlayer();
  final PomodoroActionDispatcher _pomodoroActionDispatcher =
      const PomodoroActionDispatcher();
  final PomodoroController _pomodoroController = PomodoroController();
  final FocusSessionMonitor _focusSessionMonitor = FocusSessionMonitor();
  PomodoroStatus _lastObservedPomodoroStatus = PomodoroStatus.idle;
  final VisionEventTracker _visionEventTracker = VisionEventTracker();
  final StudySessionController _studySessionController =
      StudySessionController();
  final AuthSession _authSession = AuthSession.instance;
  late final FocusSyncController _focusSyncController;

  double? _leftEyeOpenValue;
  double? _rightEyeOpenValue;
  double? _headYaw;
  double? _headPitch;
  double? _headOffsetScore;
  double? _postureDownScore;
  double? _poseNoseY;
  bool _isHeadOffsetCalibrating = true;
  final List<double> _headOffsetSamples = <double>[];
  bool _hasFace = false;

  bool _showDebugPanel = false;
  bool _showVoiceDemoPanel = false;
  bool _showVisionSourcePreview = false;
  bool _isVoiceServiceTestInFlight = false;
  bool _isAssistantDecideLoading = false;
  bool _isEventUploadDemoLoading = false;
  bool _isSpeechInitializing = false;
  bool _isSpeechListening = false;
  bool _isSpeechStopping = false;
  bool _isSpeechSubmitting = false;
  String _speechTranscript = '';
  String? _speechRecognitionError;
  String? _submittedSpeechSessionId;
  bool _isUserStatusExpanded = false;
  bool _isFocusPauseDialogVisible = false;
  bool _isPauseSuggestionDialogVisible = false;
  BuildContext? _focusDecisionDialogContext;

  static const Duration _voiceMessageHoldDuration = Duration(seconds: 5);
  static const Map<CompanionStatus, Duration> _reminderCooldowns = {
    CompanionStatus.attention: Duration(seconds: 12),
    CompanionStatus.fatigue: Duration(seconds: 15),
    CompanionStatus.distracted: Duration(seconds: 12),
    CompanionStatus.sleeping: Duration(seconds: 18),
  };
  static const Duration _idleChatterInterval = Duration(seconds: 35);
  static const Duration _idleChatterVisibleDuration = Duration(seconds: 7);
  static const bool _preferFallbackVideoForLocalTest = false;
  static const String _fallbackVideoAssetPath = 'assets/test_face.mp4';
  static const String _fallbackVideoFileName = 'desk_companion_test_face.mp4';
  static const Map<CompanionStatus, List<_ReminderClip>> _reminderClips = {
    CompanionStatus.attention: [
      _ReminderClip(
        'assets/audio/reminders/attention_1.wav',
        '眼睛有點累了，眨眨眼，讓視線休息一下。',
      ),
      _ReminderClip(
        'assets/audio/reminders/attention_3.wav',
        '先把視線移開幾秒，眼睛會舒服一點。',
      ),
    ],
    CompanionStatus.fatigue: [
      _ReminderClip(
        'assets/audio/reminders/fatigue_1.wav',
        '你看起來有點累，先休息一下再繼續。',
      ),
      _ReminderClip(
        'assets/audio/reminders/fatigue_2.wav',
        '別勉強自己，喝口水，稍微喘口氣吧。',
      ),
      _ReminderClip(
        'assets/audio/reminders/fatigue_3.wav',
        '專注很久了，現在休息一下也沒關係。',
      ),
    ],
    CompanionStatus.distracted: [
      _ReminderClip(
        'assets/audio/reminders/distracted_1.wav',
        '注意力跑掉了，先回來專注一下。',
      ),
      _ReminderClip(
        'assets/audio/reminders/distracted_2.wav',
        '注意力回來囉，接著把眼前這件事完成。',
      ),
      _ReminderClip(
        'assets/audio/reminders/distracted_3.wav',
        '好像分心了，重新找回剛才的節奏吧。',
      ),
    ],
    CompanionStatus.sleeping: [
      _ReminderClip('assets/audio/reminders/drowsy_1.wav', '快睡著了喔，坐直一點，醒醒精神。'),
      _ReminderClip('assets/audio/reminders/drowsy_2.wav', '先起來動一動吧，你需要清醒一下。'),
      _ReminderClip('assets/audio/reminders/drowsy_3.wav', '看起來很想睡，休息幾分鐘再繼續吧。'),
    ],
  };
  static const List<String> _idleChatterMessages = <String>[
    '今天節奏不錯，繼續保持。',
    '我在旁邊看著，有需要再叫我。',
    '專注條件良好，可以放心往下做。',
  ];

  int _closedEyeFrameCount = 0;
  int _distractedFrameCount = 0;
  int _postureDownFrameCount = 0;
  int _idleChatterIndex = 0;
  DateTime? _idleBubbleVisibleUntil;
  DateTime? _voiceMessagePinnedUntil;
  bool _isReminderPlaybackInFlight = false;
  CompanionStatus? _currentVoicePlaybackStatus;
  Completer<void>? _voicePlaybackCompleter;
  String? _activeSpokenReminderMessage;
  CompanionStatus? _pendingVoiceReminderStatus;
  final Map<CompanionStatus, int> _reminderClipIndexes =
      <CompanionStatus, int>{};
  final Map<CompanionStatus, DateTime> _lastReminderPlayedAt =
      <CompanionStatus, DateTime>{};
  int _fallbackVideoReplayCount = 0;
  Duration? _lastFallbackVideoDetectionPosition;
  CompanionStatus _companionStatus = CompanionStatus.normal;
  CompanionStatus _latestDetectedCompanionStatus = CompanionStatus.normal;
  String _fatigueLevel = CompanionStatus.normal.label;
  String _companionMessage = "目前狀態穩定，請保持節奏。";
  String _latestDetectedCompanionMessage = "目前狀態穩定，請保持節奏。";
  String? _lastVoiceResponseMessage;
  VoiceInteraction? _lastVoiceInteraction;
  String? _lastEventUploadDemoMessage;
  VisionEventType _lastVisionEventType = VisionEventType.normal;
  CompanionCharacterReaction _characterReaction =
      CompanionCharacterReaction.none;
  int _characterReactionSerial = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lastObservedPomodoroStatus = _pomodoroController.status;
    _pomodoroController.addListener(_handlePomodoroControllerChanged);
    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
      lowerBound: 0,
      upperBound: 1,
    )..repeat(reverse: true);
    unawaited(
      _voiceAudioPlayer.setAudioContext(
        AudioContext(
          android: const AudioContextAndroid(
            isSpeakerphoneOn: false,
            stayAwake: false,
            contentType: AndroidContentType.speech,
            usageType: AndroidUsageType.media,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
        ),
      ),
    );
    unawaited(_voiceAudioPlayer.setReleaseMode(ReleaseMode.stop));
    _voicePlayerStateSubscription = _voiceAudioPlayer.onPlayerStateChanged
        .listen((PlayerState state) {
          debugPrint('Voice player state: $state');
          if (state == PlayerState.completed) {
            _currentVoicePlaybackStatus = null;
            _completeVoicePlayback();
            unawaited(_resumeFallbackVideoAfterVoiceIfNeeded());
          } else if (state == PlayerState.stopped) {
            _currentVoicePlaybackStatus = null;
            _completeVoicePlayback();
          }
        });
    // decide() may chain two Ollama calls on the backend (intent JSON, then a
    // chat reply for mode=chat), each bounded by the backend's 120s Ollama
    // timeout. Keep the client-side budget above that sum so slow-but-healthy
    // responses aren't cut off; the local parser fallback still covers real
    // outages.
    _assistantInteractionController = AssistantInteractionController(
      decisionClient: AssistantApi(
        ApiClient(requestTimeout: const Duration(seconds: 250)),
      ),
      timeout: const Duration(seconds: 255),
    );
    _focusSyncController = FocusSyncController(authSession: _authSession);
    _focusSyncController.start(
      studySessionController: _studySessionController,
      pomodoroController: _pomodoroController,
    );
    _initializeCamera();
    _startIdleBubbleTimer();
  }

  void _startIdleBubbleTimer() {
    _idleBubbleTimer?.cancel();
    _idleBubbleTimer = Timer.periodic(_idleChatterInterval, (_) {
      if (!mounted) return;
      if (_companionStatus != CompanionStatus.normal ||
          _isVoiceMessagePinned ||
          _showDebugPanel ||
          _showVoiceDemoPanel ||
          _showVisionSourcePreview ||
          _isUserStatusExpanded) {
        return;
      }

      setState(() {
        _idleChatterIndex =
            (_idleChatterIndex + 1) % _idleChatterMessages.length;
        _idleBubbleVisibleUntil = DateTime.now().add(
          _idleChatterVisibleDuration,
        );
      });

      _idleBubbleHideTimer?.cancel();
      _idleBubbleHideTimer = Timer(_idleChatterVisibleDuration, () {
        if (!mounted || _companionStatus != CompanionStatus.normal) return;
        setState(() => _idleBubbleVisibleUntil = null);
      });
    });
  }

  Future<void> _initializeCamera() async {
    if (_preferFallbackVideoForLocalTest) {
      await _initializeFallbackVideo(reason: 'local test video mode');
      return;
    }

    setState(() {
      _isCameraInitializing = true;
      _cameraErrorMessage = null;
      _status = "正在啟動相機...";
    });

    try {
      await _nativeVisionSubscription?.cancel();
      _nativeVisionSubscription = _visionChannel.cameraResults().listen(
        _handleVisionResult,
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('Native vision stream error: $error');
        },
      );
      await _resetVisionCalibration();
      await _visionChannel.startCamera();
      if (!mounted) {
        await _visionChannel.stopCamera();
        return;
      }

      _isUsingNativeCamera = true;
      _isUsingFallbackVideo = false;
      _isCameraInitializing = false;
      _status = "相機已啟動，等待辨識...";
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      _isUsingNativeCamera = false;
      await _nativeVisionSubscription?.cancel();
      _nativeVisionSubscription = null;
      await _initializeFallbackVideo(reason: e.toString());
      if (_isUsingFallbackVideo) return;
      _isCameraInitializing = false;
      _cameraErrorMessage = "相機啟動失敗: $e";
      _status = _cameraErrorMessage!;
      setState(() {});
    }
  }

  // --- 核心偵測函式 ---
  Future<void> _initializeFallbackVideo({String? reason}) async {
    _detectionTimer?.cancel();
    _isUsingNativeCamera = false;
    await _visionChannel.stopCamera();

    try {
      final tempDir = await getTemporaryDirectory();
      final videoFile = io.File('${tempDir.path}/$_fallbackVideoFileName');
      if (!await videoFile.exists()) {
        final assetData = await rootBundle.load(_fallbackVideoAssetPath);
        await videoFile.writeAsBytes(
          assetData.buffer.asUint8List(
            assetData.offsetInBytes,
            assetData.lengthInBytes,
          ),
          flush: true,
        );
      }

      final controller = VideoPlayerController.file(videoFile);
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      _detachFallbackVideoPositionListener();
      await _fallbackVideoController?.dispose();
      _fallbackVideoController = controller;
      _fallbackVideoPath = videoFile.path;
      _lastFallbackVideoDetectionPosition = null;
      _fallbackVideoPositionListener = () {
        if (!identical(_fallbackVideoController, controller) ||
            !controller.value.isInitialized) {
          return;
        }
        _handleFallbackVideoTimeline(controller.value.position);
      };
      controller.addListener(_fallbackVideoPositionListener!);
      _isUsingFallbackVideo = true;
      _isCameraInitializing = false;
      _cameraErrorMessage = null;
      _status = '本地測試模式：使用 test_face.mp4。';
      await _resetVisionCalibration();
      if (!mounted) return;
      _startFallbackVideoDetectionLoop();
      setState(() {});
    } catch (fallbackError) {
      debugPrint('測試影片模式啟動失敗: $fallbackError');
      _isUsingFallbackVideo = false;
      _isCameraInitializing = false;
      _cameraErrorMessage = '相機啟動失敗，測試影片也無法啟動: ${reason ?? fallbackError}';
      _status = _cameraErrorMessage!;
      if (mounted) setState(() {});
    }
  }

  void _startFallbackVideoDetectionLoop() {
    _detectionTimer?.cancel();

    _detectionTimer = Timer.periodic(const Duration(milliseconds: 800), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final controller = _fallbackVideoController;
      if (_isUsingFallbackVideo &&
          controller != null &&
          controller.value.isInitialized) {
        _detectFaceFromFallbackVideo();
      }
    });
  }

  Future<void> _detectFaceFromFallbackVideo() async {
    final controller = _fallbackVideoController;
    final videoPath = _fallbackVideoPath;
    if (_isProcessing ||
        controller == null ||
        videoPath == null ||
        !controller.value.isInitialized) {
      return;
    }

    _isProcessing = true;

    try {
      final position = controller.value.position;
      final thumbnailBytes = await video_thumbnail.VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: video_thumbnail.ImageFormat.JPEG,
        timeMs: position.inMilliseconds,
        quality: 85,
      );
      if (thumbnailBytes == null) return;

      final visionResult = await _visionChannel.analyzeFrame(thumbnailBytes);
      _handleVisionResult(visionResult);
    } catch (e) {
      debugPrint('測試影片偵測失敗: $e');
    } finally {
      _isProcessing = false;
    }
  }

  void _handleFallbackVideoTimeline(Duration position) {
    final previousPosition = _lastFallbackVideoDetectionPosition;
    _lastFallbackVideoDetectionPosition = position;
    if (previousPosition == null ||
        previousPosition - position <= const Duration(seconds: 1)) {
      return;
    }

    _resetVoiceReminderCycleForVideoReplay();
  }

  void _resetVoiceReminderCycleForVideoReplay() {
    _fallbackVideoReplayCount += 1;
    _lastReminderPlayedAt.clear();
    if (_pendingVoiceReminderStatus != CompanionStatus.sleeping) {
      _clearPendingVoiceReminder();
    }
    debugPrint(
      'Voice reminder cycle reset: fallback video replayed '
      'count=$_fallbackVideoReplayCount',
    );
  }

  void _detachFallbackVideoPositionListener() {
    final controller = _fallbackVideoController;
    final listener = _fallbackVideoPositionListener;
    if (controller != null && listener != null) {
      controller.removeListener(listener);
    }
    _fallbackVideoPositionListener = null;
  }

  void _handleVisionResult(VisionResult visionResult) {
    final previousDetectedCompanionStatus = _latestDetectedCompanionStatus;
    final analysis = _companionController.analyze(visionResult);

    debugPrint(
      'Vision data: '
      'status=${analysis.status.name}, '
      'hasFace=${visionResult.hasFace}, '
      'leftEye=${visionResult.leftEyeOpen?.toStringAsFixed(3) ?? 'N/A'}, '
      'rightEye=${visionResult.rightEyeOpen?.toStringAsFixed(3) ?? 'N/A'}, '
      'headYaw=${_formatDebugValue(visionResult.headYaw)}, '
      'headPitch=${_formatDebugValue(visionResult.headPitch)}, '
      'headOffsetScore=${_formatDebugValue(visionResult.headOffsetScore)}, '
      'headOffsetCalibrating=${visionResult.isHeadOffsetCalibrating}, '
      'postureDownScore=${_formatDebugValue(analysis.postureDownResult.score)}, '
      'postureDownFrames=${analysis.postureDownResult.downFrameCount}, '
      'postureDownParts='
      'headLow=${_formatDebugValue(analysis.postureDownResult.headLowScore)}, '
      'shoulderDrop=${_formatDebugValue(analysis.postureDownResult.shoulderDropScore)}, '
      'noseDrop=${_formatDebugValue(analysis.postureDownResult.noseDropScore)}, '
      'visibility=${_formatDebugValue(analysis.postureDownResult.visibilityScore)}, '
      'sideProne=${_formatDebugValue(analysis.postureDownResult.sideProneScore)}, '
      'shoulderShrink=${_formatDebugValue(analysis.postureDownResult.shoulderShrinkScore)}, '
      'postureCalibrating=${analysis.postureDownResult.isCalibrating}, '
      'hasPose=${visionResult.hasPose}, '
      'poseSeq=${visionResult.poseSequence ?? 'N/A'}, '
      'shoulderWidth=${visionResult.shoulderWidth?.toStringAsFixed(1) ?? 'N/A'}, '
      'poseNose=(${_formatRawValue(visionResult.raw['poseNoseX'])}, ${_formatRawValue(visionResult.raw['poseNoseY'])}), '
      'ls=(${_formatRawValue(visionResult.raw['lsX'])}, ${_formatRawValue(visionResult.raw['lsY'])}), '
      'rs=(${_formatRawValue(visionResult.raw['rsX'])}, ${_formatRawValue(visionResult.raw['rsY'])})',
    );

    final rawResponse = _responseBuilder.fromVision(analysis);
    final trackingResult = _visionEventTracker.track(
      analysis,
      actionTriggered: rawResponse.actionLabel,
    );
    _studySessionController.recordVisionTrackingResult(
      trackingResult,
      isStudying: _pomodoroController.isRunning,
    );
    _focusSyncController.recordVisionTrackingResult(
      trackingResult,
      studySessionController: _studySessionController,
      pomodoroController: _pomodoroController,
    );

    _leftEyeOpenValue = visionResult.leftEyeOpen;
    _rightEyeOpenValue = visionResult.rightEyeOpen;
    _headYaw = visionResult.headYaw;
    _headPitch = visionResult.headPitch;
    _headOffsetScore = visionResult.headOffsetScore;
    _postureDownScore = analysis.postureDownResult.score;
    _poseNoseY = visionResult.poseNoseY;
    _isHeadOffsetCalibrating = visionResult.isHeadOffsetCalibrating;
    _recordHeadOffsetSample(visionResult);
    _hasFace = visionResult.hasFace;
    _closedEyeFrameCount = analysis.eyeResult.closedFrameCount;
    _distractedFrameCount = analysis.headOffsetResult.distractedFrameCount;
    _postureDownFrameCount = analysis.postureDownResult.downFrameCount;
    _latestDetectedCompanionStatus = analysis.status;
    if (analysis.postureDownResult.downFrameCount > 0 &&
        (_pendingVoiceReminderStatus == CompanionStatus.attention ||
            _pendingVoiceReminderStatus == CompanionStatus.fatigue)) {
      _clearPendingVoiceReminder();
    }
    if (analysis.status == CompanionStatus.normal) {
      _clearPendingVoiceReminder();
    }
    _syncPauseSuggestionAutoDismiss(analysis.status);
    if (analysis.status != previousDetectedCompanionStatus) {
      if (analysis.status != CompanionStatus.normal) {
        _idleBubbleVisibleUntil = null;
      }
    }
    if (trackingResult.event.type == VisionEventType.userReturned &&
        _lastVisionEventType != VisionEventType.userReturned) {
      _triggerCharacterReaction(CompanionCharacterReaction.welcome);
    }
    _lastVisionEventType = trackingResult.event.type;
    final shouldUpdateVisionMessage =
        analysis.status != previousDetectedCompanionStatus ||
        trackingResult.shouldUpdateMessage;
    if (shouldUpdateVisionMessage) {
      _latestDetectedCompanionMessage = _messageForVisionTrackingResult(
        trackingResult,
        _messageForCompanionStatus(analysis.status),
      );
    }
    if (_activeSpokenReminderMessage == null) {
      if (_companionStatus != analysis.status) {
        _syncBreathingPaceForStatus(analysis.status);
      }
      _companionStatus = analysis.status;
      _fatigueLevel = analysis.status.label;
      if (!_isVoiceMessagePinned && shouldUpdateVisionMessage) {
        _companionMessage = _latestDetectedCompanionMessage;
      }
    }

    final isPomodoroSessionActive = _pomodoroController.isActive;
    final focusInterventions = _focusSessionMonitor.update(
      status: analysis.status,
      sessionActive: isPomodoroSessionActive,
      sessionRunning: _pomodoroController.isRunning,
      sessionAutoPaused: _pomodoroController.isAutoPaused,
    );
    _handleFocusInterventions(focusInterventions);

    if (mounted) {
      setState(() {
        _status =
            "肩膀寬度: ${visionResult.shoulderWidth?.toStringAsFixed(1) ?? 'N/A'} px\n"
            "左眼: ${_leftEyeOpenValue?.toStringAsFixed(2) ?? 'N/A'} "
            "右眼: ${_rightEyeOpenValue?.toStringAsFixed(2) ?? 'N/A'}\n"
            "頭部偏移分數: ${_formatScore(_headOffsetScore)}"
            "${_isHeadOffsetCalibrating ? '（校正中）' : ''}\n"
            "趴下分數: ${_formatScore(_postureDownScore)}\n"
            "狀態: $_fatigueLevel";
      });
    }
  }

  void _handleFocusInterventions(List<FocusIntervention> interventions) {
    for (final intervention in interventions) {
      debugPrint(
        'Focus intervention: type=${intervention.type.name} '
        'status=${intervention.status.name} '
        'duration=${intervention.episodeDuration.inSeconds}s',
      );
      switch (intervention.type) {
        case FocusInterventionType.reminder:
          _requestLocalReminder(intervention.status);
          break;
        case FocusInterventionType.eventRecorded:
          _studySessionController.recordFocusEvent(intervention.status);
          break;
        case FocusInterventionType.offerPause:
          unawaited(_showFocusPauseSuggestion(intervention.status));
          break;
        case FocusInterventionType.autoPause:
          _autoPausePomodoro(intervention.status);
          break;
        case FocusInterventionType.recovered:
          unawaited(_showFocusResumeSuggestion(intervention.status));
          break;
      }
    }
  }

  void _autoPausePomodoro(CompanionStatus status) {
    if (!_pomodoroController.isRunning) return;
    _pomodoroController.pause(reason: _pauseReasonForStatus(status));
    _studySessionController.recordPomodoroPaused();
    _companionMessage = _autoPauseMessageForStatus(status);
    _latestDetectedCompanionMessage = _companionMessage;
    _lastVoiceResponseMessage = null;
    _voiceMessagePinnedUntil = DateTime.now().add(_voiceMessageHoldDuration);
    if (mounted) setState(() {});
  }

  Future<void> _showFocusPauseSuggestion(CompanionStatus status) async {
    if (!mounted ||
        _isFocusPauseDialogVisible ||
        !_pomodoroController.isRunning) {
      return;
    }

    _isFocusPauseDialogVisible = true;
    _isPauseSuggestionDialogVisible = true;
    bool? shouldPause;
    try {
      shouldPause = await _showFocusDecisionDialog(
        accentColor: const Color(0xFFFFC36B),
        icon: Icons.pause_circle_outline_rounded,
        eyebrow: _shortStatusLabel(status),
        title: '需要先停一下嗎？',
        message: _pauseSuggestionMessageForStatus(status),
        secondaryLabel: '繼續專注',
        primaryLabel: '暫停一下',
        primaryIcon: Icons.pause_rounded,
      );
    } finally {
      _focusPauseAutoDismissTimer?.cancel();
      _focusPauseAutoDismissTimer = null;
      _focusDecisionDialogContext = null;
      _isPauseSuggestionDialogVisible = false;
      _isFocusPauseDialogVisible = false;
    }

    if (shouldPause == true && _pomodoroController.isRunning) {
      _pomodoroController.pause();
      _studySessionController.recordPomodoroPaused();
    }
  }

  Future<void> _showFocusResumeSuggestion(CompanionStatus status) async {
    if (!mounted ||
        _isFocusPauseDialogVisible ||
        !_pomodoroController.isAutoPaused) {
      return;
    }

    _isFocusPauseDialogVisible = true;
    _isPauseSuggestionDialogVisible = false;
    bool? shouldResume;
    try {
      shouldResume = await _showFocusDecisionDialog(
        accentColor: const Color(0xFF9FF3D0),
        icon: Icons.auto_awesome_rounded,
        eyebrow: '狀態已恢復',
        title: '要接著完成這一輪嗎？',
        message: '你已從${_shortStatusLabel(status)}恢復，番茄鐘還停在剛才的進度。',
        secondaryLabel: '先休息',
        primaryLabel: '繼續專注',
        primaryIcon: Icons.play_arrow_rounded,
      );
    } finally {
      _focusDecisionDialogContext = null;
      _isFocusPauseDialogVisible = false;
    }

    if (shouldResume == true && _pomodoroController.isAutoPaused) {
      _pomodoroController.resume();
      _studySessionController.recordPomodoroResumed();
    }
  }

  Future<bool?> _showFocusDecisionDialog({
    required Color accentColor,
    required IconData icon,
    required String eyebrow,
    required String title,
    required String message,
    required String secondaryLabel,
    required String primaryLabel,
    required IconData primaryIcon,
  }) {
    return showGeneralDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: const Color(0x7A071725),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, _, _) {
        _focusDecisionDialogContext = dialogContext;
        return _FocusDecisionDialog(
          accentColor: accentColor,
          icon: icon,
          eyebrow: eyebrow,
          title: title,
          message: message,
          secondaryLabel: secondaryLabel,
          primaryLabel: primaryLabel,
          primaryIcon: primaryIcon,
        );
      },
      transitionBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  void _syncPauseSuggestionAutoDismiss(CompanionStatus status) {
    if (!_isPauseSuggestionDialogVisible || status != CompanionStatus.normal) {
      _focusPauseAutoDismissTimer?.cancel();
      _focusPauseAutoDismissTimer = null;
      return;
    }
    if (_focusPauseAutoDismissTimer != null) return;

    _focusPauseAutoDismissTimer = Timer(const Duration(seconds: 5), () {
      _focusPauseAutoDismissTimer = null;
      if (!mounted ||
          !_isPauseSuggestionDialogVisible ||
          _latestDetectedCompanionStatus != CompanionStatus.normal) {
        return;
      }
      final dialogContext = _focusDecisionDialogContext;
      if (dialogContext != null && Navigator.of(dialogContext).canPop()) {
        Navigator.of(dialogContext).pop(false);
      }
    });
  }

  PomodoroPauseReason _pauseReasonForStatus(CompanionStatus status) {
    switch (status) {
      case CompanionStatus.distracted:
        return PomodoroPauseReason.distracted;
      case CompanionStatus.fatigue:
        return PomodoroPauseReason.fatigue;
      case CompanionStatus.sleeping:
        return PomodoroPauseReason.sleeping;
      case CompanionStatus.userMissing:
        return PomodoroPauseReason.userMissing;
      case CompanionStatus.normal:
      case CompanionStatus.attention:
        return PomodoroPauseReason.manual;
    }
  }

  String _autoPauseMessageForStatus(CompanionStatus status) {
    return '${_shortStatusLabel(status)}持續了一段時間，番茄鐘已自動暫停。';
  }

  String _pauseSuggestionMessageForStatus(CompanionStatus status) {
    switch (status) {
      case CompanionStatus.distracted:
        return '你已經分心一段時間，可以暫停整理一下再繼續。';
      case CompanionStatus.fatigue:
        return '眼睛持續疲勞，建議先休息一下。';
      case CompanionStatus.sleeping:
        return '你看起來快睡著了，建議先暫停休息。';
      case CompanionStatus.userMissing:
        return '目前已經離席一段時間，要暫停番茄鐘嗎？';
      case CompanionStatus.normal:
      case CompanionStatus.attention:
        return '要暫停這輪專注嗎？';
    }
  }

  String _shortStatusLabel(CompanionStatus status) {
    switch (status) {
      case CompanionStatus.normal:
        return '正常狀態';
      case CompanionStatus.attention:
        return '眼睛疲勞';
      case CompanionStatus.fatigue:
        return '長時間閉眼';
      case CompanionStatus.distracted:
        return '分心狀態';
      case CompanionStatus.sleeping:
        return '疑似睡著';
      case CompanionStatus.userMissing:
        return '離席狀態';
    }
  }

  String _messageForVisionTrackingResult(
    VisionEventTrackingResult trackingResult,
    String fallbackMessage,
  ) {
    if (trackingResult.event.type == VisionEventType.userReturned) {
      return '剛剛離開了一下，要繼續這輪專注嗎？';
    }
    return fallbackMessage;
  }

  bool _isReminderCooldownReady(CompanionStatus status, DateTime now) {
    final cooldown = _reminderCooldowns[status];
    final lastPlayedAt = _lastReminderPlayedAt[status];
    if (cooldown == null || lastPlayedAt == null) return true;
    return now.difference(lastPlayedAt) >= cooldown;
  }

  void _requestLocalReminder(CompanionStatus status) {
    if (!_isReminderCooldownReady(status, DateTime.now())) {
      debugPrint('Local reminder cooldown: ${status.name}');
      return;
    }
    if (_isReminderPlaybackInFlight) {
      _queuePendingVoiceReminder(status);
      return;
    }

    _isReminderPlaybackInFlight = true;
    unawaited(_playLocalReminder(status));
  }

  Future<void> _playLocalReminder(CompanionStatus status) async {
    try {
      final clips = _reminderClips[status];
      if (clips == null || clips.isEmpty) return;

      if (_latestDetectedCompanionStatus != status) {
        debugPrint(
          'Local reminder skipped after recovery: ${status.name} -> '
          '${_latestDetectedCompanionStatus.name}',
        );
        return;
      }

      final index = (_reminderClipIndexes[status] ?? 0) % clips.length;
      _reminderClipIndexes[status] = index + 1;
      final clip = clips[index];
      final message = clip.message.isEmpty
          ? _voiceReminderMessageForStatus(status)
          : clip.message;
      debugPrint(
        'Local reminder selected: event=${_voiceEventTypeForStatus(status)} '
        'asset=${clip.assetPath}',
      );
      final assetData = await rootBundle.load(clip.assetPath);
      final audioBytes = assetData.buffer.asUint8List(
        assetData.offsetInBytes,
        assetData.lengthInBytes,
      );

      final played = await _playReminderAudio(
        audioBytes,
        status,
        message,
        null,
      );
      if (played) {
        _lastReminderPlayedAt[status] = DateTime.now();
      }
    } catch (error) {
      debugPrint('Local reminder playback failed: $error');
    } finally {
      _isReminderPlaybackInFlight = false;
      _sendPendingVoiceReminderIfReady();
    }
  }

  int _voicePriority(CompanionStatus status) {
    switch (status) {
      case CompanionStatus.sleeping:
        return 4;
      case CompanionStatus.fatigue:
        return 3;
      case CompanionStatus.distracted:
        return 2;
      case CompanionStatus.attention:
        return 1;
      case CompanionStatus.normal:
      case CompanionStatus.userMissing:
        return 0;
    }
  }

  void _queuePendingVoiceReminder(CompanionStatus status) {
    final currentStatus = _currentVoicePlaybackStatus;
    if (currentStatus != null &&
        _voicePriority(status) <= _voicePriority(currentStatus)) {
      debugPrint(
        'Voice service ignored while speaking: '
        '${currentStatus.name} -> ${status.name}',
      );
      return;
    }

    final pending = _pendingVoiceReminderStatus;
    if (pending == null || _voicePriority(status) >= _voicePriority(pending)) {
      _pendingVoiceReminderStatus = status;
      debugPrint('Local reminder pending: ${status.name}');
    }
  }

  void _sendPendingVoiceReminderIfReady() {
    final pendingStatus = _pendingVoiceReminderStatus;
    if (pendingStatus == null) return;

    _clearPendingVoiceReminder();
    _requestLocalReminder(pendingStatus);
  }

  void _clearPendingVoiceReminder() {
    _pendingVoiceReminderStatus = null;
  }

  void _resetVoiceReminderCandidate() {
    _clearPendingVoiceReminder();
  }

  String _voiceEventTypeForStatus(CompanionStatus status) {
    switch (status) {
      case CompanionStatus.attention:
        return 'vision.attention_warning';
      case CompanionStatus.fatigue:
        return 'vision.fatigue_detected';
      case CompanionStatus.distracted:
        return 'vision.distracted';
      case CompanionStatus.sleeping:
        return 'vision.sleeping';
      case CompanionStatus.normal:
      case CompanionStatus.userMissing:
        return 'vision.normal';
    }
  }

  String _voiceReminderMessageForStatus(CompanionStatus status) {
    switch (status) {
      case CompanionStatus.attention:
        return '眼睛有點累了，先眨眨眼休息一下。';
      case CompanionStatus.fatigue:
        return '你看起來很累，先停一下，讓眼睛休息。';
      case CompanionStatus.distracted:
        return '注意力跑掉了，先回來專注一下。';
      case CompanionStatus.sleeping:
        return '看起來快睡著了，先坐直休息一下。';
      case CompanionStatus.normal:
      case CompanionStatus.userMissing:
        return '';
    }
  }

  Future<bool> _playReminderAudio(
    Uint8List? audioBytes,
    CompanionStatus status,
    String message,
    Duration? duration,
  ) async {
    if (audioBytes == null || audioBytes.isEmpty) {
      debugPrint('Voice playback skipped: empty audio bytes');
      return false;
    }
    Completer<void>? playbackCompleter;
    try {
      await _voiceAudioPlayer.stop();
      playbackCompleter = Completer<void>();
      _voicePlaybackCompleter = playbackCompleter;
      _currentVoicePlaybackStatus = status;
      _triggerCharacterReaction(CompanionCharacterReaction.reminder);
      _showSpokenReminder(status, message);
      debugPrint(
        'Voice playback starting: ${audioBytes.length} bytes '
        'status=${status.name} text=$message',
      );
      await _voiceAudioPlayer.play(BytesSource(audioBytes));
      final timeout =
          (duration ?? const Duration(seconds: 8)) + const Duration(seconds: 2);
      try {
        await playbackCompleter.future.timeout(timeout);
      } on TimeoutException {
        debugPrint('Voice playback completion timed out: ${status.name}');
        await _voiceAudioPlayer.stop();
      }
      return true;
    } catch (error) {
      _currentVoicePlaybackStatus = null;
      debugPrint('Voice playback failed: $error');
      return false;
    } finally {
      if (identical(_voicePlaybackCompleter, playbackCompleter)) {
        _voicePlaybackCompleter = null;
        _finishSpokenReminder();
      }
    }
  }

  void _completeVoicePlayback() {
    final completer = _voicePlaybackCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  void _showSpokenReminder(CompanionStatus status, String message) {
    _activeSpokenReminderMessage = message;
    _idleBubbleVisibleUntil = null;
    if (_companionStatus != status) {
      _syncBreathingPaceForStatus(status);
    }
    _companionStatus = status;
    _fatigueLevel = status.label;
    _companionMessage = message;
    if (mounted) setState(() {});
  }

  void _finishSpokenReminder() {
    _activeSpokenReminderMessage = null;
    if (_companionStatus != _latestDetectedCompanionStatus) {
      _syncBreathingPaceForStatus(_latestDetectedCompanionStatus);
    }
    _companionStatus = _latestDetectedCompanionStatus;
    _fatigueLevel = _latestDetectedCompanionStatus.label;
    if (!_isVoiceMessagePinned) {
      _companionMessage = _latestDetectedCompanionMessage;
    }
    if (mounted) setState(() {});
  }

  Future<void> _playVoiceServiceAudio(
    Uint8List? audioBytes,
    CompanionStatus status,
  ) async {
    await _playReminderAudio(
      audioBytes,
      status,
      _voiceReminderMessageForStatus(status),
      null,
    );
  }

  Future<void> _resumeFallbackVideoAfterVoiceIfNeeded() async {
    final controller = _fallbackVideoController;
    if (!_isUsingFallbackVideo || controller == null) return;
    if (!controller.value.isInitialized || controller.value.isPlaying) return;

    try {
      await controller.play();
      debugPrint('Fallback video resumed after voice playback');
    } catch (error) {
      debugPrint('Fallback video resume failed: $error');
    }
  }

  String _messageForCompanionStatus(CompanionStatus status) {
    switch (status) {
      case CompanionStatus.normal:
        return '目前狀態穩定，請保持節奏。';
      case CompanionStatus.attention:
        return '偵測到注意力波動，先把視線帶回目標。';
      case CompanionStatus.fatigue:
        return '偵測到眼睛疲勞，建議休息一下。';
      case CompanionStatus.distracted:
        return '偵測到視線偏離，請把注意力帶回螢幕。';
      case CompanionStatus.sleeping:
        return '偵測到疑似睡著，建議坐直或短暫休息。';
      case CompanionStatus.userMissing:
        return '暫時沒有偵測到完整使用者。';
    }
  }

  Future<void> _callNativeToast(String msg) async {
    try {
      await _visionChannel.showToast(msg);
    } catch (e) {
      debugPrint("手動 Toast 呼叫失敗: $e");
    }
  }

  Future<void> _testVoiceService() async {
    if (_isVoiceServiceTestInFlight) return;

    setState(() => _isVoiceServiceTestInFlight = true);
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    try {
      final result = await _voiceServiceClient.sendReminder(
        text: '語音測試成功，Desk Companion 已經可以說話了。',
        status: 'manual_test',
        eventType: 'system.voice_test',
        source: 'manual-test',
      );
      if (!result.generated) {
        throw VoiceServiceException(result.reason ?? '語音服務沒有回傳可播放的音訊。');
      }

      await _playVoiceServiceAudio(
        result.audioBytes,
        CompanionStatus.attention,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('語音服務正常（${result.mode ?? 'unknown'}）'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('語音測試失敗：$error\n服務位置：${_voiceServiceClient.baseUrl}'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 8),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isVoiceServiceTestInFlight = false);
      }
    }
  }

  Future<void> _runEventUploadDemo() async {
    if (_isEventUploadDemoLoading) return;

    setState(() {
      _isEventUploadDemoLoading = true;
      _lastEventUploadDemoMessage = '正在上傳事件 Demo...';
    });

    final result = await _focusSyncController.uploadDemoEvent(
      studySessionController: _studySessionController,
      pomodoroController: _pomodoroController,
    );

    if (!mounted) return;

    final message = result.success
        ? '事件上傳成功：送出 ${result.attemptedCount} 筆，新增 ${result.savedCount} 筆，重複 ${result.skippedDuplicateCount} 筆。'
        : '事件上傳失敗：${result.message ?? '未知錯誤'}';
    final detail = result.sessionId == null
        ? message
        : '$message\nSession: ${result.sessionId}';

    setState(() {
      _isEventUploadDemoLoading = false;
      _lastEventUploadDemoMessage = detail;
    });

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(detail),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  void _closeVoiceDialog() {
    setState(() {
      _lastVoiceInteraction = null;
      _lastVoiceResponseMessage = null;
      _voiceMessagePinnedUntil = null;
    });
  }

  void _closeAllDeveloperPanels() {
    setState(() {
      _hideVoiceDemoPanelState();
      _showDebugPanel = false;
      _showVisionSourcePreview = false;
    });
  }

  void _hideVoiceDemoPanelState() {
    unawaited(_deviceSpeechRecognitionService.cancel());
    _showVoiceDemoPanel = false;
    _resetSpeechDemoState();
  }

  Future<void> _toggleSpeechDemo() async {
    if (_isSpeechListening || _deviceSpeechRecognitionService.isListening) {
      await _stopSpeechDemo();
      return;
    }
    await _startSpeechDemo();
  }

  Future<void> _startSpeechDemo() async {
    if (_isSpeechInitializing ||
        _isSpeechStopping ||
        _isSpeechSubmitting ||
        _isAssistantDecideLoading) {
      return;
    }

    setState(() {
      _isSpeechInitializing = true;
      _speechRecognitionError = null;
      _speechTranscript = '';
      _submittedSpeechSessionId = null;
    });

    try {
      if (_voiceAudioPlayer.state == PlayerState.playing ||
          _voiceAudioPlayer.state == PlayerState.paused) {
        await _voiceAudioPlayer.stop();
      }

      final available = await _deviceSpeechRecognitionService.initialize(
        onStatus: _handleDeviceSpeechStatus,
        onError: _handleDeviceSpeechError,
      );
      if (!mounted) return;
      if (!available) {
        setState(() {
          _isSpeechInitializing = false;
          _speechRecognitionError = '這台裝置沒有可用的語音辨識服務。';
        });
        return;
      }

      debugPrint(
        'STT locale=${_deviceSpeechRecognitionService.preferredLocaleId} '
        'reportedByDevice='
        '${_deviceSpeechRecognitionService.preferredLocaleReportedByDevice}',
      );

      setState(() {
        _isSpeechInitializing = false;
        _isSpeechListening = true;
      });
      await _deviceSpeechRecognitionService.start(
        onResult: _handleDeviceSpeechResult,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSpeechInitializing = false;
        _isSpeechListening = false;
        _isSpeechStopping = false;
        _speechRecognitionError = '無法開始語音辨識：$error';
      });
    }
  }

  Future<void> _stopSpeechDemo() async {
    if (_isSpeechStopping) return;
    setState(() {
      _isSpeechListening = false;
      _isSpeechStopping = true;
    });
    try {
      await _deviceSpeechRecognitionService.stop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSpeechStopping = false;
        _speechRecognitionError = '停止語音辨識失敗：$error';
      });
    }
  }

  Future<void> _cancelSpeechDemo({bool clearTranscript = true}) async {
    await _deviceSpeechRecognitionService.cancel();
    if (!mounted) return;
    setState(() {
      _resetSpeechDemoState(clearTranscript: clearTranscript);
    });
  }

  void _handleDeviceSpeechStatus(String status) {
    if (!mounted) return;
    setState(() {
      _isSpeechListening = status == 'listening';
      if (status == 'done' || status == 'notListening') {
        _isSpeechStopping = false;
      }
    });
  }

  void _handleDeviceSpeechError(String error) {
    debugPrint(
      'STT error: locale=${_deviceSpeechRecognitionService.preferredLocaleId} '
      'error=$error',
    );
    if (!mounted) return;
    setState(() {
      _isSpeechInitializing = false;
      _isSpeechListening = false;
      _isSpeechStopping = false;
      _speechRecognitionError = _friendlySpeechError(error);
    });
  }

  void _handleDeviceSpeechResult(VoiceRecognitionResult result) {
    if (!mounted) return;
    final text = result.bestText.trim();
    debugPrint(
      'STT result: locale=${result.language?.tag} '
      'final=${result.isFinal} text="$text"',
    );
    setState(() {
      _speechTranscript = text;
      if (result.isFinal) {
        _isSpeechListening = false;
        _isSpeechStopping = false;
      }
    });

    if (result.isFinal &&
        text.isNotEmpty &&
        _submittedSpeechSessionId != result.sessionId) {
      _submittedSpeechSessionId = result.sessionId;
      unawaited(_submitRecognizedSpeech(text));
    }
  }

  Future<void> _submitRecognizedSpeech(String text) async {
    if (_isSpeechSubmitting || _isAssistantDecideLoading) return;
    setState(() {
      _isSpeechSubmitting = true;
      _speechRecognitionError = null;
      _assistantTextController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    });

    try {
      await _runAssistantTextDemo();
    } finally {
      if (mounted) {
        setState(() => _isSpeechSubmitting = false);
      }
    }
  }

  String _friendlySpeechError(String error) {
    if (error.contains('permission')) {
      return '沒有麥克風權限，請到系統設定允許後再試一次。';
    }
    if (error.contains('speech_timeout')) {
      return '沒有聽到你說話，點一下麥克風再試一次。';
    }
    if (error.contains('no_match')) {
      return '這句沒有聽清楚，可以靠近一點再說一次。';
    }
    if (error.contains('network')) {
      return '語音辨識目前無法連線，請檢查網路後再試一次。';
    }
    if (error.contains('language_not_supported') ||
        error.contains('language_unavailable')) {
      return '裝置尚未提供繁體中文語音模型，請安裝中文（台灣）語音資料後再試。';
    }
    return '語音辨識失敗：$error';
  }

  void _resetSpeechDemoState({bool clearTranscript = false}) {
    _isSpeechInitializing = false;
    _isSpeechListening = false;
    _isSpeechStopping = false;
    _isSpeechSubmitting = false;
    _speechRecognitionError = null;
    _submittedSpeechSessionId = null;
    if (clearTranscript) {
      _speechTranscript = '';
    }
  }

  Future<void> _runVoiceDemo(String caseId) async {
    if (_isVoiceDemoLoading) return;

    setState(() {
      _isVoiceDemoLoading = true;
    });

    try {
      final results = await _mockVoiceResultLoader.loadResults();
      var selectedResult = results.isEmpty ? null : results.first;
      for (final result in results) {
        if (result.caseId == caseId) {
          selectedResult = result;
          break;
        }
      }
      if (selectedResult?.caseId != caseId) {
        selectedResult = null;
      }
      final selectedInteraction = selectedResult == null
          ? null
          : _voiceInteractionController.handle(selectedResult);

      if (selectedInteraction == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("找不到語音 Demo 資料: $caseId"),
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }

      _applyVoiceInteraction(selectedInteraction);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("語音 Demo 載入失敗: $e"),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isVoiceDemoLoading = false;
        });
      }
    }
  }

  Future<void> _runAssistantTextDemo() async {
    final text = _assistantTextController.text.trim();
    if (text.isEmpty || _isAssistantDecideLoading) return;

    setState(() {
      _isAssistantDecideLoading = true;
    });
    _triggerCharacterReaction(CompanionCharacterReaction.thinking);

    try {
      final result = await _assistantInteractionController.handleText(
        text: text,
        context: _buildAssistantContext(),
        accessToken: _authSession.accessToken,
      );
      if (!mounted) return;
      _applyAssistantInteractionResult(text, result);
    } catch (error) {
      if (!mounted) return;
      _triggerCharacterReaction(CompanionCharacterReaction.error);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Assistant decide failed: $error'),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isAssistantDecideLoading = false;
        });
      }
    }
  }

  Map<String, dynamic> _buildAssistantContext() {
    return <String, dynamic>{
      'pomodoro': <String, dynamic>{
        'status': _pomodoroController.status.name,
        'remainingSeconds': _pomodoroController.remaining.inSeconds,
        'totalSeconds': _pomodoroController.totalDuration.inSeconds,
      },
      'vision': <String, dynamic>{
        'status': _companionStatus.name,
        'fatigueLevel': _fatigueLevel,
        'hasFace': _hasFace,
      },
      'todaySummary': _studySessionController.buildSummary(_pomodoroController),
    };
  }

  void _applyAssistantInteractionResult(
    String text,
    AssistantInteractionResult result,
  ) {
    if (result.pendingAction != null) {
      _pendingActionController.setPendingAction(result.pendingAction!);
      _triggerCharacterReaction(CompanionCharacterReaction.confirmation);
    }

    if (result.shouldRunAction && result.command != null) {
      final interaction = VoiceInteraction(
        result: _voiceResultFromText(text),
        command: result.command!,
        response: result.response,
      );
      _applyVoiceInteraction(interaction);
      return;
    }

    _companionMessage = result.response.message;
    _lastVoiceResponseMessage = result.response.message;
    _voiceMessagePinnedUntil = DateTime.now().add(_voiceMessageHoldDuration);
    if (result.pendingAction == null) {
      _triggerCharacterReaction(CompanionCharacterReaction.success);
    }
    setState(() {});

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.response.message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  VoiceRecognitionResult _voiceResultFromText(String text) {
    return VoiceRecognitionResult(
      sessionId: 'assistant-text',
      eventType: VoiceEventType.finalResult,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      transcript: text,
      formattedTranscript: text,
      isFinal: true,
      candidates: [VoiceCandidate(text: text, confidence: 1)],
    );
  }

  void _confirmPendingAssistantAction() {
    final pending = _pendingActionController.consume();
    if (pending == null) return;

    final interaction = VoiceInteraction(
      result: _voiceResultFromText(pending.command.sourceText),
      command: pending.command,
      response: _responseBuilder.fromVoiceCommand(pending.command),
    );
    _applyVoiceInteraction(interaction);
  }

  void _cancelPendingAssistantAction() {
    _pendingActionController.clear();
    setState(() {
      _companionMessage = '已取消待確認的動作。';
      _lastVoiceResponseMessage = _companionMessage;
      _voiceMessagePinnedUntil = DateTime.now().add(_voiceMessageHoldDuration);
    });
    _triggerCharacterReaction(CompanionCharacterReaction.error);
  }

  void _applyVoiceInteraction(VoiceInteraction interaction) {
    _lastVoiceInteraction = interaction;
    _studySessionController.recordVoiceCommand(interaction.command);
    final previousPomodoroStatus = _pomodoroController.status;
    final actionResult = _pomodoroActionDispatcher.dispatch(
      command: interaction.command,
      controller: _pomodoroController,
      studySession: _studySessionController,
    );
    _focusSyncController.recordVoiceInteraction(
      interaction,
      studySessionController: _studySessionController,
      pomodoroController: _pomodoroController,
      actionLabel: actionResult.response.actionLabel,
    );
    _recordPomodoroAction(
      interaction.command,
      previousStatus: previousPomodoroStatus,
      actionLabel: actionResult.response.actionLabel,
    );
    _companionMessage = actionResult.response.message;
    _lastVoiceResponseMessage = actionResult.response.message;
    _voiceMessagePinnedUntil = DateTime.now().add(_voiceMessageHoldDuration);
    _triggerCharacterReaction(CompanionCharacterReaction.success);

    if (mounted) {
      setState(() {});
    }
  }

  void _recordPomodoroAction(
    VoiceCommand command, {
    required PomodoroStatus previousStatus,
    String? actionLabel,
  }) {
    switch (command.type) {
      case VoiceCommandType.startPomodoro:
        if (actionLabel == 'start_pomodoro') {
          _studySessionController.recordPomodoroStarted();
        }
        break;
      case VoiceCommandType.pausePomodoro:
        if (actionLabel == 'pause_pomodoro') {
          _studySessionController.recordPomodoroPaused();
        }
        break;
      case VoiceCommandType.resumePomodoro:
        if (actionLabel == 'resume_pomodoro') {
          _studySessionController.recordPomodoroResumed();
        }
        break;
      case VoiceCommandType.stopPomodoro:
        if (actionLabel == 'stop_pomodoro') {
          _studySessionController.recordPomodoroStopped();
        }
        break;
      case VoiceCommandType.requestBreak:
        if (previousStatus == PomodoroStatus.running &&
            actionLabel == 'start_eye_break') {
          _studySessionController.recordPomodoroPaused();
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

    _focusSyncController.recordPomodoroAction(
      command,
      studySessionController: _studySessionController,
      pomodoroController: _pomodoroController,
      previousStatus: previousStatus,
      actionLabel: actionLabel,
    );
  }

  void _handlePomodoroControllerChanged() {
    final currentStatus = _pomodoroController.status;
    final previousStatus = _lastObservedPomodoroStatus;
    if (currentStatus == PomodoroStatus.running &&
        (previousStatus == PomodoroStatus.idle ||
            previousStatus == PomodoroStatus.completed)) {
      _focusSessionMonitor.beginSession();
      unawaited(
        _focusSyncController.startFocusRound(
          studySessionController: _studySessionController,
          pomodoroController: _pomodoroController,
        ),
      );
    } else if (currentStatus == PomodoroStatus.paused &&
        previousStatus == PomodoroStatus.running) {
      unawaited(
        _focusSyncController.updateCurrentRound(
          status: FocusRoundStatus.paused,
          studySessionController: _studySessionController,
          pomodoroController: _pomodoroController,
        ),
      );
    } else if (currentStatus == PomodoroStatus.running &&
        previousStatus == PomodoroStatus.paused) {
      unawaited(
        _focusSyncController.updateCurrentRound(
          status: FocusRoundStatus.active,
          studySessionController: _studySessionController,
          pomodoroController: _pomodoroController,
        ),
      );
    } else if (currentStatus == PomodoroStatus.idle &&
        (previousStatus == PomodoroStatus.running ||
            previousStatus == PomodoroStatus.paused)) {
      unawaited(
        _focusSyncController.updateCurrentRound(
          status: FocusRoundStatus.stopped,
          endReason: FocusRoundEndReason.userStopped,
          endedAt: DateTime.now(),
          studySessionController: _studySessionController,
          pomodoroController: _pomodoroController,
        ),
      );
    }
    if (currentStatus == PomodoroStatus.completed &&
        previousStatus != PomodoroStatus.completed) {
      _studySessionController.recordPomodoroCompleted();
      _focusSyncController.recordPomodoroCompleted(
        studySessionController: _studySessionController,
        pomodoroController: _pomodoroController,
      );
      _companionMessage = '這輪專注完成了，先休息一下吧。';
      _lastVoiceResponseMessage = null;
      _voiceMessagePinnedUntil = null;
      _triggerCharacterReaction(CompanionCharacterReaction.focusCompleted);
    }
    if (currentStatus == PomodoroStatus.idle ||
        currentStatus == PomodoroStatus.completed) {
      _focusSessionMonitor.endSession();
    }
    _lastObservedPomodoroStatus = currentStatus;
    if (mounted) setState(() {});
  }

  bool get _isVoiceMessagePinned {
    final pinnedUntil = _voiceMessagePinnedUntil;
    return pinnedUntil != null && DateTime.now().isBefore(pinnedUntil);
  }

  Future<void> _restartCamera() async {
    _detectionTimer?.cancel();
    _focusSessionMonitor.resetDetectionState();
    _lastReminderPlayedAt.clear();
    await _visionChannel.stopCamera();
    _detachFallbackVideoPositionListener();
    await _fallbackVideoController?.dispose();
    _fallbackVideoController = null;
    _fallbackVideoPath = null;
    _isUsingNativeCamera = false;
    _isUsingFallbackVideo = false;
    _companionController.reset();
    _visionEventTracker.reset();
    await _initializeCamera();
  }

  Future<void> _resetVisionCalibration() async {
    _companionController.reset();
    _focusSessionMonitor.resetDetectionState();
    _lastReminderPlayedAt.clear();
    _visionEventTracker.reset();
    _headOffsetSamples.clear();
    _closedEyeFrameCount = 0;
    _distractedFrameCount = 0;
    _postureDownFrameCount = 0;
    _headOffsetScore = null;
    _postureDownScore = null;
    _leftEyeOpenValue = null;
    _rightEyeOpenValue = null;
    _headYaw = null;
    _headPitch = null;
    _poseNoseY = null;
    _hasFace = false;
    _isHeadOffsetCalibrating = true;
    _companionStatus = CompanionStatus.normal;
    _fatigueLevel = CompanionStatus.normal.label;
    _companionMessage = '正在校正視覺基準，請自然坐好並看向前方。';
    _resetVoiceReminderCandidate();

    try {
      await _visionChannel.resetVision();
    } catch (e) {
      debugPrint("重設視覺校正失敗: $e");
    }

    if (mounted) setState(() {});
  }

  Color _getStatusColor() {
    switch (_companionStatus) {
      case CompanionStatus.fatigue:
        return const Color(0xFFE85D75);
      case CompanionStatus.attention:
      case CompanionStatus.distracted:
      case CompanionStatus.sleeping:
        return const Color(0xFFFFB648);
      case CompanionStatus.normal:
      case CompanionStatus.userMissing:
        return const Color(0xFF68C7F2);
    }
  }

  Color _getStatusGlowColor() {
    switch (_companionStatus) {
      case CompanionStatus.normal:
        return const Color(0xFF9FF3D0);
      case CompanionStatus.attention:
      case CompanionStatus.distracted:
        return const Color(0xFFFFD36B);
      case CompanionStatus.fatigue:
      case CompanionStatus.sleeping:
        return const Color(0xFFFF7A3D);
      case CompanionStatus.userMissing:
        return const Color(0xFF9AC7FF);
    }
  }

  Duration _breathingDurationForStatus(CompanionStatus status) {
    switch (status) {
      case CompanionStatus.normal:
        return const Duration(seconds: 4);
      case CompanionStatus.attention:
      case CompanionStatus.distracted:
        return const Duration(seconds: 2);
      case CompanionStatus.fatigue:
      case CompanionStatus.sleeping:
        return const Duration(milliseconds: 850);
      case CompanionStatus.userMissing:
        return const Duration(seconds: 4);
    }
  }

  void _syncBreathingPaceForStatus(CompanionStatus status) {
    final duration = _breathingDurationForStatus(status);
    if (_breathingController.duration != duration) {
      _breathingController.duration = duration;
    }

    if (status == CompanionStatus.userMissing) {
      _breathingController.stop();
      _breathingController.value = 0.35;
      return;
    }

    if (!_breathingController.isAnimating) {
      _breathingController.repeat(reverse: true);
    }
  }

  double _statusPulseValue() {
    if (_companionStatus == CompanionStatus.userMissing) return 0.35;

    final value = _breathingController.value;
    if (_companionStatus == CompanionStatus.fatigue ||
        _companionStatus == CompanionStatus.sleeping) {
      final firstPulse = value < 0.32 ? value / 0.32 : 0.0;
      final secondPulse = value > 0.46 && value < 0.72
          ? (value - 0.46) / 0.26
          : 0.0;
      return (firstPulse.clamp(0.0, 1.0) * 0.85 + secondPulse.clamp(0.0, 1.0))
          .clamp(0.0, 1.0)
          .toDouble();
    }

    return Curves.easeInOut.transform(value);
  }

  String _getCompanionMessage() {
    return _companionMessage;
  }

  bool get _shouldShowCompanionBubble {
    if (_activeSpokenReminderMessage != null) return true;
    if (_isVoiceMessagePinned) return true;

    final visibleUntil = _idleBubbleVisibleUntil;
    return visibleUntil != null && DateTime.now().isBefore(visibleUntil);
  }

  String get _companionBubbleMessage {
    final spokenMessage = _activeSpokenReminderMessage;
    if (spokenMessage != null) return spokenMessage;
    if (_isVoiceMessagePinned) return _getCompanionMessage();

    switch (_companionStatus) {
      case CompanionStatus.normal:
        return _idleChatterMessages[_idleChatterIndex];
      case CompanionStatus.attention:
        return '眼睛開始累囉，先慢慢把注意力拉回來。';
      case CompanionStatus.distracted:
        return '欸，視線飄走了，回來陪我一下。';
      case CompanionStatus.fatigue:
        return '眼睛真的累了，先休息一下比較帥。';
      case CompanionStatus.sleeping:
        return '看起來快睡著啦，先坐直醒一下。';
      case CompanionStatus.userMissing:
        return '我先待機，回來再陪你。';
    }
  }

  CompanionCharacterMood get _characterMood {
    return switch (_companionStatus) {
      CompanionStatus.normal => CompanionCharacterMood.neutral,
      CompanionStatus.attention => CompanionCharacterMood.attentive,
      CompanionStatus.fatigue => CompanionCharacterMood.tired,
      CompanionStatus.distracted => CompanionCharacterMood.distracted,
      CompanionStatus.sleeping => CompanionCharacterMood.sleeping,
      CompanionStatus.userMissing => CompanionCharacterMood.away,
    };
  }

  void _triggerCharacterReaction(CompanionCharacterReaction reaction) {
    _characterReaction = reaction;
    _characterReactionSerial += 1;
    if (mounted) setState(() {});
  }

  String get _displayName {
    final email = _authSession.email;
    if (email == null || email.isEmpty) return 'Reader';
    return email.split('@').first;
  }

  // ignore: unused_element
  String get _timerHudText {
    if (_pomodoroController.isActive) {
      return _pomodoroController.formattedRemaining;
    }
    return '待機';
  }

  String get _compactTimerHudText {
    if (_pomodoroController.isActive) {
      return _pomodoroController.formattedRemaining;
    }
    return '待機';
  }

  String get _todayFocusHudText {
    final minutes = _studySessionController.focusedDuration.inMinutes;
    if (minutes == 0) return '0m';
    return '${minutes}m';
  }

  // ignore: unused_element
  String get _statusHudText {
    switch (_companionStatus) {
      case CompanionStatus.fatigue:
        return '需要休息';
      case CompanionStatus.attention:
        return "似乎有些疲倦了，記得留意狀態。";
      case CompanionStatus.distracted:
        return "視線偏離了一段時間，先把注意力帶回螢幕吧。";
      case CompanionStatus.sleeping:
        return "偵測到疑似睡著，先坐直休息一下。";
      case CompanionStatus.userMissing:
        return '暫時離開';
      case CompanionStatus.normal:
        return _pomodoroController.isRunning ? '專注中' : '準備中';
    }
  }

  String get _compactStatusHudText {
    switch (_companionStatus) {
      case CompanionStatus.normal:
        return _pomodoroController.isRunning ? '專注' : '穩定';
      case CompanionStatus.attention:
        return '注意';
      case CompanionStatus.fatigue:
        return '疲勞';
      case CompanionStatus.distracted:
        return '分心';
      case CompanionStatus.sleeping:
        return '睡著';
      case CompanionStatus.userMissing:
        return '離席';
    }
  }

  String _formatEyeValue(double? value) {
    if (value == null) return "--";
    return value.toStringAsFixed(2);
  }

  String _formatAngle(double? value) {
    if (value == null) return "--";
    return "${value.toStringAsFixed(1)}°";
  }

  String _formatDebugValue(double? value) {
    if (value == null) return "N/A";
    return value.toStringAsFixed(3);
  }

  String _formatScore(double? value) {
    if (value == null) return "--";
    return value.toStringAsFixed(1);
  }

  void _recordHeadOffsetSample(VisionResult visionResult) {
    if (!visionResult.hasFace ||
        visionResult.isHeadOffsetCalibrating ||
        visionResult.headOffsetScore == null) {
      return;
    }

    _headOffsetSamples.add(visionResult.headOffsetScore!);
    if (_headOffsetSamples.length % 30 == 0) {
      _printHeadOffsetStats();
    }
  }

  void _printHeadOffsetStats() {
    if (_headOffsetSamples.isEmpty) return;

    final sorted = List<double>.from(_headOffsetSamples)..sort();
    final minValue = sorted.first;
    final maxValue = sorted.last;
    final average =
        sorted.reduce((total, value) => total + value) / sorted.length;
    final p90 = _percentile(sorted, 0.90);
    final p95 = _percentile(sorted, 0.95);

    debugPrint(
      'HeadOffset stats: '
      'samples=${sorted.length}, '
      'min=${minValue.toStringAsFixed(1)}, '
      'avg=${average.toStringAsFixed(1)}, '
      'p90=${p90.toStringAsFixed(1)}, '
      'p95=${p95.toStringAsFixed(1)}, '
      'max=${maxValue.toStringAsFixed(1)}',
    );
  }

  double _percentile(List<double> sortedValues, double percentile) {
    final index = ((sortedValues.length - 1) * percentile).round();
    return sortedValues[index.clamp(0, sortedValues.length - 1)];
  }

  String _formatRawValue(dynamic value) {
    if (value is num) return value.toDouble().toStringAsFixed(3);
    return "N/A";
  }

  Widget _buildTopStatusDot() {
    final color = _getStatusColor();
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.45),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }

  Widget _buildTopHud() {
    return Positioned(
      top: 18,
      left: 18,
      right: 18,
      child: SafeArea(
        bottom: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildUserStatusCard(),
            const Spacer(),
            const SizedBox(width: 12),
            _buildAiPreferenceButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildUserStatusCard() {
    if (!_isUserStatusExpanded) {
      return GestureDetector(
        onTap: _handleUserStatusTap,
        child: SizedBox(
          width: 50,
          height: 50,
          child: Center(child: _buildAvatarBadge(isCompact: true)),
        ),
      );
    }

    return GestureDetector(
      onTap: _handleUserStatusTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        height: 80,
        width: 250,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRect(
          child: Row(
            children: [
              _buildAvatarBadge(),
              const SizedBox(width: 10),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: _buildExpandedUserStatus(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarBadge({bool isCompact = false}) {
    final color = _getStatusColor();
    final size = isCompact ? 48.0 : 44.0;
    final innerMargin = isCompact ? 4.0 : 3.0;
    return AnimatedBuilder(
      animation: _breathingController,
      builder: (context, child) {
        final glow = _breathingController.value;
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withValues(alpha: 0.45 + glow * 0.35),
              width: 1.2 + glow * 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.22 + glow * 0.28),
                blurRadius: 10 + glow * 14,
                spreadRadius: glow * 1.8,
              ),
            ],
          ),
          child: Container(
            margin: EdgeInsets.all(innerMargin),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.34),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.26)),
            ),
            child: Center(
              child: Text(
                _displayName.characters.first.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildExpandedUserStatus() {
    return Column(
      key: const ValueKey('expanded_user_status'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Flexible(
              child: _buildHudChip(_compactStatusHudText, _getStatusColor()),
            ),
            _buildHudChip('$_todayFocusHudText 專注', Colors.white),
            Flexible(
              child: _buildHudChip(
                _compactTimerHudText,
                const Color(0xFF79D2F5),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHudChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildAiPreferenceButton() {
    return Tooltip(
      message: '工具與偏好',
      child: GestureDetector(
        onTap: _showHomeToolSheet,
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(
            Icons.smart_toy_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }

  void _handleUserStatusTap() {
    if (_isUserStatusExpanded) {
      _userStatusCollapseTimer?.cancel();
      setState(() => _isUserStatusExpanded = false);
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ProfileDetailScreen()),
      ).then((_) {
        if (!mounted || !_isUserStatusExpanded) return;
        setState(() => _isUserStatusExpanded = false);
      });
      return;
    }

    setState(() => _isUserStatusExpanded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isUserStatusExpanded) return;
      _scheduleUserStatusCollapse();
    });
  }

  void _scheduleUserStatusCollapse() {
    _userStatusCollapseTimer?.cancel();
    _userStatusCollapseTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      if (!_isUserStatusExpanded) return;
      setState(() => _isUserStatusExpanded = false);
    });
  }

  void _showHomeToolSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.82;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxSheetHeight),
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x22000000),
                    blurRadius: 22,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.smart_toy_rounded, color: Color(0xFF2F7ED8)),
                        SizedBox(width: 10),
                        Text(
                          '工具與偏好',
                          style: TextStyle(
                            color: Color(0xFF20324D),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildToolSheetAction(
                      icon: Icons.record_voice_over_rounded,
                      title: '語音 Demo',
                      subtitle: '開發測試用，正式版會拿掉。',
                      isActive: _showVoiceDemoPanel,
                      onTap: () {
                        Navigator.pop(context);
                        setState(() {
                          if (_showVoiceDemoPanel) {
                            _hideVoiceDemoPanelState();
                          } else {
                            _showVoiceDemoPanel = true;
                            _showDebugPanel = false;
                            _showVisionSourcePreview = false;
                          }
                        });
                      },
                    ),
                    _buildToolSheetAction(
                      icon: Icons.visibility_rounded,
                      title: '視覺 Debug',
                      subtitle: '查看眼睛、頭部與趴下偵測數據。',
                      isActive: _showDebugPanel,
                      onTap: () {
                        Navigator.pop(context);
                        setState(() {
                          _showDebugPanel = !_showDebugPanel;
                          if (_showDebugPanel) {
                            _hideVoiceDemoPanelState();
                            _showVisionSourcePreview = false;
                          }
                        });
                      },
                    ),
                    _buildToolSheetAction(
                      icon: Icons.videocam_rounded,
                      title: 'Preview',
                      subtitle: '切換顯示測試影片或相機畫面。',
                      isActive: _showVisionSourcePreview,
                      onTap: () {
                        Navigator.pop(context);
                        setState(() {
                          _showVisionSourcePreview = !_showVisionSourcePreview;
                          if (_showVisionSourcePreview) {
                            _hideVoiceDemoPanelState();
                            _showDebugPanel = false;
                          }
                        });
                      },
                    ),
                    if (_showVoiceDemoPanel ||
                        _showDebugPanel ||
                        _showVisionSourcePreview)
                      _buildToolSheetAction(
                        icon: Icons.close_rounded,
                        title: '關閉所有 Demo',
                        subtitle: '回到乾淨的主監測畫面。',
                        isActive: false,
                        onTap: () {
                          Navigator.pop(context);
                          _closeAllDeveloperPanels();
                        },
                      ),
                    const SizedBox(height: 14),
                    const Divider(height: 1, color: Color(0x1A20324D)),
                    const SizedBox(height: 14),
                    _buildAiPreferenceTile('安靜模式', '只記錄狀態，不主動打擾。'),
                    _buildAiPreferenceTile('回覆語氣', '之後可切換溫和、嚴格或鼓勵。'),
                    _buildAiPreferenceTile('提醒敏感度', '調整疲勞與分心提醒頻率。'),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildToolSheetAction({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFFEAF7FF)
                : Colors.white.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isActive
                  ? const Color(0xFFB7E3F7)
                  : const Color(0x1420324D),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isActive
                    ? const Color(0xFF2F7ED8)
                    : const Color(0xFF63758C),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF20324D),
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF63758C),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (isActive)
                const Icon(
                  Icons.check_circle_rounded,
                  color: Color(0xFF2F7ED8),
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  void _showAiPreferenceSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 22,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.smart_toy_rounded, color: Color(0xFF2F7ED8)),
                    SizedBox(width: 10),
                    Text(
                      'AI 偏好設定',
                      style: TextStyle(
                        color: Color(0xFF20324D),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _buildAiPreferenceTile('安靜模式', '只記錄狀態，不主動打擾。'),
                _buildAiPreferenceTile('回覆語氣', '之後可切換溫和、嚴格或鼓勵。'),
                _buildAiPreferenceTile('提醒敏感度', '調整疲勞與分心提醒頻率。'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAiPreferenceTile(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF79D2F5),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF20324D),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF63758C),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildAttentionBanner() {
    if (_companionStatus != CompanionStatus.attention &&
        _companionStatus != CompanionStatus.distracted &&
        _companionStatus != CompanionStatus.sleeping) {
      return const SizedBox.shrink();
    }
    final isDistracted = _companionStatus == CompanionStatus.distracted;
    final isSleeping = _companionStatus == CompanionStatus.sleeping;

    return Positioned(
      top: 96,
      left: 18,
      right: 18,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFFFD8A8)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.visibility_rounded, color: Color(0xFFFFA94D)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isSleeping
                    ? "偵測到疑似睡著，先坐直休息一下。"
                    : isDistracted
                    ? "偵測到視線偏離，請把注意力帶回螢幕。"
                    : "偵測到眨眼頻繁，請留意疲勞狀態。",
                style: const TextStyle(
                  color: Color(0xFF6B4E16),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompanionSpeechBubble() {
    if (!_shouldShowCompanionBubble) return const SizedBox.shrink();

    final glowColor = _getStatusGlowColor();

    return Positioned(
      top: 108,
      left: 64,
      right: 82,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.34),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: glowColor.withValues(alpha: 0.20),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      color: glowColor,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        child: Text(
                          _companionBubbleMessage,
                          key: ValueKey(_companionBubbleMessage),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF25324A),
                            fontSize: 14,
                            height: 1.45,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 18,
                bottom: -6,
                child: Transform.rotate(
                  angle: 0.78,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      border: Border(
                        right: BorderSide(
                          color: Colors.white.withValues(alpha: 0.24),
                        ),
                        bottom: BorderSide(
                          color: Colors.white.withValues(alpha: 0.24),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildFatigueAlertCard() {
    if (_companionStatus != CompanionStatus.fatigue) {
      return const SizedBox.shrink();
    }

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
              color: Color(0x2AE85D75),
              blurRadius: 24,
              offset: Offset(0, 12),
            ),
          ],
          border: Border.all(color: const Color(0xFFFFD0D7), width: 1.4),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 62,
              height: 62,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xFFFFEEF1),
                  borderRadius: BorderRadius.all(Radius.circular(20)),
                ),
                child: Icon(
                  Icons.health_and_safety_rounded,
                  color: Color(0xFFE85D75),
                  size: 34,
                ),
              ),
            ),
            SizedBox(height: 16),
            Text(
              "疲勞提醒",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF20324D),
              ),
            ),
            SizedBox(height: 10),
            Text(
              "偵測到使用者連續閉眼，可能出現疲勞狀態。\n建議暫時休息、喝水，或稍微離開螢幕。",
              style: TextStyle(
                fontSize: 15,
                height: 1.6,
                color: Color(0xFF52657D),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildBottomCompanionPanel() {
    return Positioned(
      left: 18,
      right: 18,
      bottom: 26,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFD6EEFA)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF7FF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.favorite_rounded,
                      color: Color(0xFF4EA9E6),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      "Desk Companion",
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF20324D),
                      ),
                    ),
                  ),
                  _buildTopStatusDot(),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                _getCompanionMessage(),
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.6,
                  color: Color(0xFF52657D),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassBottomNavigationBar() {
    return GlassBottomNavBar(
      activeTab: AppNavTab.home,
      animation: _breathingController,
      glowColor: _getStatusGlowColor(),
      glowPulseBuilder: () {
        if (_companionStatus == CompanionStatus.userMissing) return 0.0;
        return _statusPulseValue();
      },
      onHomeTap: _closeAllDeveloperPanels,
      onStatisticsTap: () async {
        await _focusSyncController.flushNow(
          studySessionController: _studySessionController,
          pomodoroController: _pomodoroController,
        );
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const StatisticsScreen()),
        );
      },
      onTasksTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const TasksScreen()),
        );
      },
      onSettingsTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ProfileHubScreen()),
        );
      },
    );
  }

  Widget _buildVoiceDemoButtons() {
    if (!_showVoiceDemoPanel) return const SizedBox.shrink();

    return Positioned(
      left: 16,
      right: 16,
      bottom: GlassBottomNavBar.contentBottomPadding,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.42,
          ),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFD8EEF8)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.record_voice_over_rounded,
                        color: Color(0xFF2F7ED8),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '語音 Demo',
                          style: TextStyle(
                            color: Color(0xFF20324D),
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '關閉語音 Demo',
                        onPressed: () {
                          setState(_hideVoiceDemoPanelState);
                        },
                        icon: const Icon(Icons.close_rounded),
                        color: const Color(0xFF63758C),
                        iconSize: 20,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  Text(
                    '語音服務：${_voiceServiceClient.baseUrl}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF63758C),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildSpeechRecognitionDemo(),
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: Color(0x1A20324D)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _assistantTextController,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _runAssistantTextDemo(),
                    decoration: InputDecoration(
                      hintText: '輸入文字測試 Assistant，例如：幫我開25分鐘番茄鐘',
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFFF5FBFF),
                      prefixIcon: const Icon(Icons.smart_toy_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFD8EEF8)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFD8EEF8)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isAssistantDecideLoading
                          ? null
                          : _runAssistantTextDemo,
                      icon: _isAssistantDecideLoading
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded),
                      label: const Text('Assistant decide'),
                    ),
                  ),
                  if (_pendingActionController.hasPendingAction) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _confirmPendingAssistantAction,
                            icon: const Icon(Icons.check_rounded),
                            label: const Text('確認執行'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _cancelPendingAssistantAction,
                            icon: const Icon(Icons.close_rounded),
                            label: const Text('取消'),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isVoiceServiceTestInFlight
                          ? null
                          : _testVoiceService,
                      icon: _isVoiceServiceTestInFlight
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.volume_up_rounded),
                      label: const Text('測試語音輸出'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isEventUploadDemoLoading
                          ? null
                          : _runEventUploadDemo,
                      icon: _isEventUploadDemoLoading
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_upload_rounded),
                      label: const Text('事件上傳 Demo'),
                    ),
                  ),
                  if (_lastEventUploadDemoMessage != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF7FF),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFD8EEF8)),
                      ),
                      child: Text(
                        _lastEventUploadDemoMessage!,
                        style: const TextStyle(
                          color: Color(0xFF31465F),
                          fontSize: 12,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildVoiceDemoChip("開始25", "final_start_pomodoro"),
                      _buildVoiceDemoChip(
                        "開始15",
                        "final_start_custom_pomodoro",
                      ),
                      _buildVoiceDemoChip("暫停", "final_pause_timer"),
                      _buildVoiceDemoChip("繼續", "final_resume_timer"),
                      _buildVoiceDemoChip("中止", "final_stop_timer"),
                      _buildVoiceDemoChip("摘要", "final_summary_timer"),
                      _buildVoiceDemoChip("剩多久", "final_timer_status"),
                      _buildVoiceDemoChip("我累了", "final_report_tired"),
                      _buildVoiceDemoChip("分心", "final_report_distracted"),
                      _buildVoiceDemoChip("休息", "final_request_break"),
                      _buildVoiceDemoChip(
                        "確認",
                        "final_low_confidence_pomodoro",
                      ),
                      _buildVoiceDemoChip("未知", "final_unknown_low_confidence"),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpeechRecognitionDemo() {
    final isBusy =
        _isSpeechInitializing || _isSpeechStopping || _isSpeechSubmitting;
    final statusText = switch ((
      _isSpeechInitializing,
      _isSpeechListening,
      _isSpeechStopping,
      _isSpeechSubmitting,
    )) {
      (true, _, _, _) => '正在準備麥克風…',
      (_, true, _, _) => '正在聆聽…',
      (_, _, true, _) => '正在整理辨識結果…',
      (_, _, _, true) => '正在把文字送給角色…',
      _ => '裝置語音轉文字',
    };
    final buttonLabel = switch ((
      _isSpeechInitializing,
      _isSpeechListening,
      _isSpeechStopping,
      _isSpeechSubmitting,
    )) {
      (true, _, _, _) => '準備中',
      (_, true, _, _) => '停止並送出',
      (_, _, true, _) => '整理中',
      (_, _, _, true) => '送出中',
      _ => '開始語音辨識',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              _isSpeechListening ? Icons.graphic_eq_rounded : Icons.mic_rounded,
              size: 20,
              color: _isSpeechListening
                  ? const Color(0xFFDF5D67)
                  : const Color(0xFF2F7ED8),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                statusText,
                style: const TextStyle(
                  color: Color(0xFF20324D),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              _deviceSpeechRecognitionService.preferredLocaleId,
              style: const TextStyle(
                color: Color(0xFF63758C),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _speechTranscript.isEmpty ? '辨識文字會顯示在這裡' : _speechTranscript,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _speechTranscript.isEmpty
                ? const Color(0xFF8A99AA)
                : const Color(0xFF31465F),
            fontSize: 13,
            height: 1.4,
            fontWeight: _speechTranscript.isEmpty
                ? FontWeight.w400
                : FontWeight.w600,
          ),
        ),
        if (!_deviceSpeechRecognitionService.preferredLocaleReportedByDevice)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              '模擬器未列出繁中模型，這次已強制使用 zh-TW。',
              style: TextStyle(
                color: Color(0xFF9A6A17),
                fontSize: 10,
                height: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (_speechRecognitionError != null) ...[
          const SizedBox(height: 6),
          Text(
            _speechRecognitionError!,
            style: const TextStyle(
              color: Color(0xFFB33A48),
              fontSize: 11,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: isBusy || _isAssistantDecideLoading
                    ? null
                    : _toggleSpeechDemo,
                icon: isBusy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        _isSpeechListening
                            ? Icons.stop_rounded
                            : Icons.mic_rounded,
                      ),
                label: Text(buttonLabel),
              ),
            ),
            if (_isSpeechListening || _isSpeechStopping) ...[
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: '取消這次語音辨識',
                onPressed: () => _cancelSpeechDemo(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildVoiceDemoChip(String label, String caseId) {
    return SizedBox(
      height: 36,
      child: ElevatedButton(
        onPressed: _isVoiceDemoLoading ? null : () => _runVoiceDemo(caseId),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFEAF7FF),
          foregroundColor: const Color(0xFF2F7ED8),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.24)),
          ),
        ),
        child: _isVoiceDemoLoading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(label),
      ),
    );
  }

  Widget _buildVoiceDialogPanel() {
    final interaction = _lastVoiceInteraction;
    if (interaction == null) return const SizedBox.shrink();
    final responseMessage =
        _lastVoiceResponseMessage ?? interaction.response.message;

    final confidence = interaction.command.confidence;
    final confidenceText = confidence == null
        ? "信心值: N/A"
        : "信心值: ${(confidence * 100).toStringAsFixed(0)}%";
    final timerText = _pomodoroController.isActive
        ? "番茄鐘 ${_pomodoroController.formattedRemaining}"
        : "番茄鐘未啟動";

    return Positioned(
      left: 18,
      right: 18,
      bottom: _showVoiceDemoPanel || _showDebugPanel
          ? MediaQuery.sizeOf(context).height * 0.42 +
                GlassBottomNavBar.contentBottomPadding +
                12
          : GlassBottomNavBar.contentBottomPadding + 52,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.34,
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFD8EEF8)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEAF7FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.record_voice_over_rounded,
                          color: Color(0xFF2F7ED8),
                          size: 19,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          "語音 Demo",
                          style: TextStyle(
                            color: Color(0xFF20324D),
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      Flexible(
                        child: Text(
                          timerText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF2F7ED8),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '關閉語音對話',
                        onPressed: _closeVoiceDialog,
                        icon: const Icon(Icons.close_rounded),
                        color: const Color(0xFF63758C),
                        iconSize: 20,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "你說：${interaction.result.bestText}",
                    style: const TextStyle(
                      color: Color(0xFF31465F),
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Desk Companion：$responseMessage",
                    style: const TextStyle(
                      color: Color(0xFF31465F),
                      fontSize: 14,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildVoiceMetaChip(confidenceText),
                      _buildVoiceMetaChip("視覺狀態: $_fatigueLevel"),
                      _buildVoiceMetaChip("畫面: ${_hasFace ? "有人臉" : "未見人臉"}"),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVoiceMetaChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF7FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF3F607D),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildDebugPanel() {
    if (!_showDebugPanel) return const SizedBox.shrink();

    return Positioned(
      left: 16,
      right: 16,
      bottom: GlassBottomNavBar.contentBottomPadding,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.54,
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFD8EEF8)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: DefaultTextStyle(
              style: const TextStyle(
                color: Color(0xFF31465F),
                fontSize: 14,
                height: 1.5,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.bug_report_rounded,
                          color: Color(0xFF2F7ED8),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            "開發資訊",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF20324D),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '關閉視覺 Debug',
                          onPressed: () {
                            setState(() => _showDebugPanel = false);
                          },
                          icon: const Icon(Icons.close_rounded),
                          color: const Color(0xFF63758C),
                          iconSize: 20,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text("左眼開度：${_formatEyeValue(_leftEyeOpenValue)}"),
                    Text("右眼開度：${_formatEyeValue(_rightEyeOpenValue)}"),
                    Text(
                      "頭部偏移分數：${_formatScore(_headOffsetScore)}"
                      "${_isHeadOffsetCalibrating ? "（校正中）" : ""}",
                    ),
                    Text("連續分心次數：$_distractedFrameCount"),
                    Text("趴下分數：${_formatScore(_postureDownScore)}"),
                    Text("連續趴下次數：$_postureDownFrameCount"),
                    Text(
                      "趴下細項："
                      "頭低 ${_formatScore(_companionController.lastAnalysis?.postureDownResult.headLowScore)} / "
                      "肩降 ${_formatScore(_companionController.lastAnalysis?.postureDownResult.shoulderDropScore)} / "
                      "鼻降 ${_formatScore(_companionController.lastAnalysis?.postureDownResult.noseDropScore)} / "
                      "側趴 ${_formatScore(_companionController.lastAnalysis?.postureDownResult.sideProneScore)} / "
                      "肩縮 ${_formatScore(_companionController.lastAnalysis?.postureDownResult.shoulderShrinkScore)}",
                    ),
                    Text("Pose 鼻子 Y：${_formatScore(_poseNoseY)}"),
                    Text("Yaw 參考值：${_formatAngle(_headYaw)}"),
                    Text("Pitch 參考值：${_formatAngle(_headPitch)}"),
                    Text("連續閉眼次數：$_closedEyeFrameCount"),
                    Text("是否偵測到人臉：${_hasFace ? "是" : "否"}"),
                    Text("目前狀態：$_fatigueLevel"),
                    Text("視覺事件：${_lastVisionEventType.storageValue}"),
                    Text(
                      "統計：疲勞 ${_studySessionController.fatigueEventCount} 次，"
                      "注意 ${_studySessionController.attentionWarningCount} 次，"
                      "離開 ${_studySessionController.awayDuration.inSeconds} 秒",
                    ),
                    const SizedBox(height: 10),
                    Text(_status),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _restartCamera,
                            icon: const Icon(Icons.cameraswitch_rounded),
                            label: const Text("重啟相機"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF57BEEB),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _callNativeToast("手動觸發提醒測試"),
                            icon: const Icon(
                              Icons.notifications_active_rounded,
                            ),
                            label: const Text("測試提醒"),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF2F7ED8),
                              side: const BorderSide(color: Color(0xFFB7E3F7)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              backgroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _resetVisionCalibration,
                        icon: const Icon(Icons.center_focus_strong_rounded),
                        label: const Text("重設視覺校正"),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF2F7ED8),
                          side: const BorderSide(color: Color(0xFFB7E3F7)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildDebugToggleButton() {
    return _buildDeveloperToolDock();
  }

  Widget _buildDeveloperToolDock() {
    return Positioned(
      left: 18,
      right: 18,
      bottom: 158,
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildToolDockButton(
              icon: Icons.record_voice_over_rounded,
              label: '語音 Demo',
              isActive: _showVoiceDemoPanel,
              onTap: () {
                setState(() {
                  if (_showVoiceDemoPanel) {
                    _hideVoiceDemoPanelState();
                  } else {
                    _showVoiceDemoPanel = true;
                    _showDebugPanel = false;
                    _showVisionSourcePreview = false;
                  }
                });
              },
            ),
            const SizedBox(width: 10),
            _buildToolDockButton(
              icon: Icons.visibility_rounded,
              label: '視覺 Demo',
              isActive: _showDebugPanel,
              onTap: () {
                setState(() {
                  _showDebugPanel = !_showDebugPanel;
                  if (_showDebugPanel) {
                    _hideVoiceDemoPanelState();
                    _showVisionSourcePreview = false;
                  }
                });
              },
            ),
            const SizedBox(width: 10),
            _buildToolDockButton(
              icon: Icons.videocam_rounded,
              label: 'Preview',
              isActive: _showVisionSourcePreview,
              onTap: () {
                setState(() {
                  _showVisionSourcePreview = !_showVisionSourcePreview;
                  if (_showVisionSourcePreview) {
                    _hideVoiceDemoPanelState();
                    _showDebugPanel = false;
                  }
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolDockButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: isActive
                ? Colors.white.withValues(alpha: 0.92)
                : Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive
                  ? const Color(0xFFB7E3F7)
                  : Colors.white.withValues(alpha: 0.26),
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x18000000),
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: isActive ? const Color(0xFF2F7ED8) : Colors.white,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? const Color(0xFF2F7ED8) : Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _detectionTimer?.cancel();
      _breathingController.stop();
      unawaited(_visionChannel.stopCamera());
      unawaited(
        _focusSyncController.flushNow(
          studySessionController: _studySessionController,
          pomodoroController: _pomodoroController,
        ),
      );
      _fallbackVideoController?.pause();
    } else if (state == AppLifecycleState.resumed) {
      if (_isUsingFallbackVideo) {
        _fallbackVideoController?.play();
        _startFallbackVideoDetectionLoop();
      } else if (_isUsingNativeCamera) {
        unawaited(_resumeNativeCamera());
      } else {
        _initializeCamera();
      }
      if (!_breathingController.isAnimating) {
        _breathingController.repeat(reverse: true);
      }
      _focusSyncController.start(
        studySessionController: _studySessionController,
        pomodoroController: _pomodoroController,
      );
    }
  }

  Future<void> _resumeNativeCamera() async {
    try {
      await _visionChannel.startCamera();
    } catch (error) {
      debugPrint('Native camera resume failed: $error');
      if (mounted) {
        await _initializeFallbackVideo(reason: error.toString());
      }
    }
  }

  Widget _buildCameraBackground() {
    return RepaintBoundary(
      child: Live2DCharacterBackground(
        mood: _characterMood,
        reaction: _characterReaction,
        reactionSerial: _characterReactionSerial,
      ),
    );
  }

  Widget _buildVisionSourcePreviewPanel() {
    if (!_showVisionSourcePreview) return const SizedBox.shrink();

    return Positioned(
      right: 16,
      bottom: GlassBottomNavBar.contentBottomPadding,
      width: 168,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFD8EEF8)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x26000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.visibility_rounded,
                    color: Color(0xFF2F7ED8),
                    size: 17,
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      '相機預覽',
                      style: TextStyle(
                        color: Color(0xFF20324D),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '關閉相機預覽',
                    onPressed: () {
                      setState(() => _showVisionSourcePreview = false);
                    },
                    icon: const Icon(Icons.close_rounded),
                    color: const Color(0xFF63758C),
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: _buildVisionSourcePreview(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVisionSourcePreview() {
    if (_isUsingNativeCamera && io.Platform.isAndroid) {
      return const ClipRect(
        child: AndroidView(
          viewType: 'com.example.desk_companion/camera_preview',
        ),
      );
    }

    final fallbackVideoController = _fallbackVideoController;
    if (_isUsingFallbackVideo &&
        fallbackVideoController != null &&
        fallbackVideoController.value.isInitialized) {
      final videoSize = fallbackVideoController.value.size;
      return ClipRect(
        child: SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: videoSize.width,
              height: videoSize.height,
              child: VideoPlayer(fallbackVideoController),
            ),
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFF10283D),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: const Color(0x990A2A43)),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Text(
                _cameraErrorMessage ??
                    (_isCameraInitializing ? "正在啟動相機..." : "等待相機畫面..."),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  height: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _printHeadOffsetStats();
    _detectionTimer?.cancel();
    unawaited(
      _focusSyncController.close(
        studySessionController: _studySessionController,
        pomodoroController: _pomodoroController,
      ),
    );
    _userStatusCollapseTimer?.cancel();
    _idleBubbleTimer?.cancel();
    _idleBubbleHideTimer?.cancel();
    _focusPauseAutoDismissTimer?.cancel();
    _breathingController.dispose();
    unawaited(_visionChannel.stopCamera());
    unawaited(_nativeVisionSubscription?.cancel() ?? Future<void>.value());
    _detachFallbackVideoPositionListener();
    _fallbackVideoController?.dispose();
    _completeVoicePlayback();
    _voicePlayerStateSubscription?.cancel();
    _voiceAudioPlayer.dispose();
    unawaited(_deviceSpeechRecognitionService.cancel());
    _assistantTextController.dispose();
    _pomodoroController.removeListener(_handlePomodoroControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5FBFF),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildCameraBackground(),

          // Soft overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0x330A2A43),
                  Colors.transparent,
                  const Color(0x260A2A43),
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),

          _buildCompanionSpeechBubble(),
          _buildTopHud(),
          _buildVisionSourcePreviewPanel(),
          _buildGlassBottomNavigationBar(),
          _buildVoiceDialogPanel(),
          _buildVoiceDemoButtons(),
          _buildDebugPanel(),
        ],
      ),
    );
  }
}

class _FocusDecisionDialog extends StatelessWidget {
  const _FocusDecisionDialog({
    required this.accentColor,
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.message,
    required this.secondaryLabel,
    required this.primaryLabel,
    required this.primaryIcon,
  });

  final Color accentColor;
  final IconData icon;
  final String eyebrow;
  final String title;
  final String message;
  final String secondaryLabel;
  final String primaryLabel;
  final IconData primaryIcon;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 390),
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            decoration: BoxDecoration(
              color: const Color(0xFF17334B).withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.26)),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.24),
                  blurRadius: 34,
                  spreadRadius: 1,
                ),
                const BoxShadow(
                  color: Color(0x52000000),
                  blurRadius: 28,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: accentColor.withValues(alpha: 0.38),
                        ),
                      ),
                      child: Icon(icon, color: accentColor, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        eyebrow,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: accentColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    height: 1.25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  message,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 14,
                    height: 1.55,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white.withValues(alpha: 0.82),
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.22),
                            ),
                          ),
                        ),
                        child: Text(
                          secondaryLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pop(context, true),
                        icon: Icon(primaryIcon, size: 20),
                        label: Text(
                          primaryLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: const Color(0xFF17334B),
                          minimumSize: const Size.fromHeight(48),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
