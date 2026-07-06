import 'dart:async';
import 'dart:io' as io;
import 'dart:ui' show ImageFilter;

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as video_thumbnail;

import '../auth/auth_session.dart';
import '../companion/companion_controller.dart';
import '../companion/companion_response_builder.dart';
import '../focus/pomodoro_action_dispatcher.dart';
import '../focus/pomodoro_controller.dart';
import '../focus/study_session_controller.dart';
import '../vision/companion_state_evaluator.dart';
import '../vision/vision_channel.dart';
import '../vision/vision_event.dart';
import '../vision/vision_event_tracker.dart';
import '../vision/vision_result.dart';
import '../voice/voice_command.dart';
import '../voice/mock_voice_result_loader.dart';
import '../voice/voice_interaction_controller.dart';
import '../widgets/glass_bottom_nav_bar.dart';
import '../widgets/rive_asset_background.dart';
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
  CameraController? _cameraController;
  VideoPlayerController? _fallbackVideoController;
  VoidCallback? _fallbackVideoPositionListener;

  Timer? _detectionTimer;
  Timer? _userStatusCollapseTimer;
  Timer? _idleBubbleTimer;
  Timer? _idleBubbleHideTimer;
  StreamSubscription<PlayerState>? _voicePlayerStateSubscription;
  late final AnimationController _breathingController;
  bool _isProcessing = false;
  bool _isCameraInitializing = true;
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
  final AudioPlayer _voiceAudioPlayer = AudioPlayer();
  final PomodoroActionDispatcher _pomodoroActionDispatcher =
      const PomodoroActionDispatcher();
  final PomodoroController _pomodoroController = PomodoroController();
  PomodoroStatus _lastObservedPomodoroStatus = PomodoroStatus.idle;
  final VisionEventTracker _visionEventTracker = VisionEventTracker();
  final StudySessionController _studySessionController =
      StudySessionController();
  final AuthSession _authSession = AuthSession.instance;

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
  bool _isUserStatusExpanded = false;

  static const Duration _voiceMessageHoldDuration = Duration(seconds: 5);
  static const Duration _postureReminderFollowUpDelay = Duration(seconds: 8);
  static const int _postureReminderMaxPerEpisode = 2;
  static const int _postureRecoveryFramesRequired = 3;
  static const Map<CompanionStatus, Duration> _reminderEvidenceWindows = {
    CompanionStatus.attention: Duration(seconds: 4),
    CompanionStatus.fatigue: Duration(seconds: 3),
    CompanionStatus.distracted: Duration(seconds: 3),
    CompanionStatus.drowsy: Duration(seconds: 3),
  };
  static const Map<CompanionStatus, int> _reminderEvidenceThresholds = {
    CompanionStatus.attention: 3,
    CompanionStatus.fatigue: 2,
    CompanionStatus.distracted: 2,
    CompanionStatus.drowsy: 2,
  };
  static const Map<CompanionStatus, Duration> _reminderCooldowns = {
    CompanionStatus.attention: Duration(seconds: 12),
    CompanionStatus.fatigue: Duration(seconds: 15),
    CompanionStatus.distracted: Duration(seconds: 12),
    CompanionStatus.drowsy: Duration(seconds: 15),
  };
  static const Duration _idleChatterInterval = Duration(seconds: 35);
  static const Duration _idleChatterVisibleDuration = Duration(seconds: 7);
  static const bool _preferFallbackVideoForLocalTest = false;
  static const String _fallbackVideoAssetPath = 'assets/test.mp4';
  static const String _fallbackVideoFileName = 'desk_companion_test.mp4';
  static const Map<CompanionStatus, List<_ReminderClip>> _reminderClips = {
    CompanionStatus.attention: [
      _ReminderClip(
        'assets/audio/reminders/attention_1.wav',
        '眼睛有點累了，眨眨眼，讓視線休息一下。',
      ),
      _ReminderClip(
        'assets/audio/reminders/attention_2.wav',
        '看螢幕有一會兒了，稍微放鬆一下眼睛吧。',
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
    CompanionStatus.drowsy: [
      _ReminderClip('assets/audio/reminders/drowsy_1.wav', '快睡著了喔，坐直一點，醒醒精神。'),
      _ReminderClip('assets/audio/reminders/drowsy_2.wav', '先起來動一動吧，你需要清醒一下。'),
      _ReminderClip('assets/audio/reminders/drowsy_3.wav', '看起來很想睡，休息幾分鐘再繼續吧。'),
    ],
    CompanionStatus.postureDown: [
      _ReminderClip(
        'assets/audio/reminders/posture_down_1.wav',
        '你趴下了，先坐起來再繼續。',
      ),
      _ReminderClip(
        'assets/audio/reminders/posture_down_2.wav',
        '先把身體坐正，別讓自己趴著睡著了。',
      ),
      _ReminderClip(
        'assets/audio/reminders/posture_down_3.wav',
        '起來伸展一下吧，換個姿勢會舒服一點。',
      ),
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
  final Map<CompanionStatus, List<DateTime>> _reminderEvidenceByStatus =
      <CompanionStatus, List<DateTime>>{};
  final Map<CompanionStatus, DateTime> _lastReminderPlayedAt =
      <CompanionStatus, DateTime>{};
  bool _isPostureReminderEpisodeActive = false;
  DateTime? _postureReminderEpisodeStartedAt;
  int _postureReminderCount = 0;
  int _postureRecoveryFrames = 0;
  int _fallbackVideoReplayCount = 0;
  Duration? _lastFallbackVideoDetectionPosition;
  CompanionStatus _companionStatus = CompanionStatus.normal;
  CompanionStatus _latestDetectedCompanionStatus = CompanionStatus.normal;
  String _fatigueLevel = CompanionStatus.normal.label;
  String _companionMessage = "目前狀態穩定，請保持節奏。";
  String _latestDetectedCompanionMessage = "目前狀態穩定，請保持節奏。";
  String? _lastVoiceResponseMessage;
  VoiceInteraction? _lastVoiceInteraction;
  VisionEventType _lastVisionEventType = VisionEventType.normal;

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
            usageType: AndroidUsageType.assistanceSonification,
            audioFocus: AndroidAudioFocus.none,
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
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException('noCamera', '找不到可用的相機。');
      }

      final camera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      _cameraController = controller;
      _isUsingFallbackVideo = false;
      _isCameraInitializing = false;
      _status = "相機已啟動，等待辨識...";
      _startCameraDetectionLoop();
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      await _initializeFallbackVideo(reason: e.toString());
      if (_isUsingFallbackVideo) return;
      _isCameraInitializing = false;
      _cameraErrorMessage = "相機啟動失敗: $e";
      _status = _cameraErrorMessage!;
      setState(() {});
    }
  }

  void _startCameraDetectionLoop() {
    _detectionTimer?.cancel();

    _detectionTimer = Timer.periodic(const Duration(milliseconds: 800), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final controller = _cameraController;
      if (controller != null && controller.value.isInitialized) {
        _detectFaceFromCamera();
      }
    });
  }

  // --- 核心偵測函式 ---
  Future<void> _initializeFallbackVideo({String? reason}) async {
    _detectionTimer?.cancel();

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
      _status = '本地測試模式：使用 test.mp4。';
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
    _reminderEvidenceByStatus.clear();
    _lastReminderPlayedAt.clear();
    _resetPostureReminderEpisode();
    if (_pendingVoiceReminderStatus != CompanionStatus.postureDown) {
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

  Future<void> _detectFaceFromCamera() async {
    final controller = _cameraController;
    if (_isProcessing ||
        controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture) {
      return;
    }

    _isProcessing = true;

    XFile? frameFile;

    try {
      frameFile = await controller.takePicture();
      final imageFile = io.File(frameFile.path);
      final Uint8List imageBytes = await imageFile.readAsBytes();

      final visionResult = await _visionChannel.analyzeFrame(imageBytes);

      _handleVisionResult(visionResult);
    } catch (e) {
      debugPrint("辨識錯誤: $e");
    } finally {
      _isProcessing = false;
      if (frameFile != null) {
        final file = io.File(frameFile.path);
        if (file.existsSync()) {
          try {
            file.deleteSync();
          } catch (e) {
            debugPrint("刪檔失敗");
          }
        }
      }
    }
  }

  void _handleVisionResult(VisionResult visionResult) {
    final previousCompanionStatus = _latestDetectedCompanionStatus;
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

    final response = _responseBuilder.fromVision(analysis);
    final trackingResult = _visionEventTracker.track(
      analysis,
      actionTriggered: response.actionLabel,
    );
    _studySessionController.recordVisionTrackingResult(
      trackingResult,
      isStudying: _pomodoroController.isRunning,
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
    if (analysis.status != previousCompanionStatus) {
      if (analysis.status != CompanionStatus.normal) {
        _idleBubbleVisibleUntil = null;
      }
    }
    _lastVisionEventType = trackingResult.event.type;
    final shouldUpdateVisionMessage =
        analysis.status != previousCompanionStatus ||
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

    _maybePlayVisionReminder(analysis);

    if (trackingResult.shouldNotify &&
        trackingResult.event.type == VisionEventType.fatigueDetected &&
        _leftEyeOpenValue != null &&
        _rightEyeOpenValue != null) {
      _showFatigueAlert(
        leftProbability: _leftEyeOpenValue!,
        rightProbability: _rightEyeOpenValue!,
        message: response.message,
      );
    }

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

  String _messageForVisionTrackingResult(
    VisionEventTrackingResult trackingResult,
    String fallbackMessage,
  ) {
    if (trackingResult.event.type == VisionEventType.userReturned) {
      return '剛剛離開了一下，要繼續這輪專注嗎？';
    }
    return fallbackMessage;
  }

  void _maybePlayVisionReminder(CompanionAnalysis analysis) {
    final status = _voiceStatusForAnalysis(analysis);
    if (status == CompanionStatus.postureDown) {
      _handlePostureReminderEpisode();
      return;
    }

    _updatePostureReminderRecovery(analysis);
    if (_isPostureReminderEpisodeActive) return;
    if (!_shouldSpeakStatus(status)) return;
    if (!_recordReminderEvidence(status, DateTime.now())) return;

    _requestLocalReminder(status);
  }

  CompanionStatus _voiceStatusForAnalysis(CompanionAnalysis analysis) {
    // The posture detector deliberately holds this count through short pose
    // dropouts, so speech does not disappear when a prone face leaves frame.
    if (analysis.postureDownResult.downFrameCount >= 2) {
      return CompanionStatus.postureDown;
    }
    return analysis.status;
  }

  bool _recordReminderEvidence(CompanionStatus status, DateTime now) {
    if (!_isReminderCooldownReady(status, now)) {
      _reminderEvidenceByStatus.remove(status);
      return false;
    }

    final window = _reminderEvidenceWindows[status];
    final threshold = _reminderEvidenceThresholds[status];
    if (window == null || threshold == null) return false;

    final evidence = _reminderEvidenceByStatus.putIfAbsent(
      status,
      () => <DateTime>[],
    );
    evidence.removeWhere((sample) => now.difference(sample) > window);
    evidence.add(now);
    if (evidence.length < threshold) {
      debugPrint(
        'Reminder evidence: status=${status.name} '
        'count=${evidence.length}/$threshold window=${window.inSeconds}s',
      );
      return false;
    }

    evidence.clear();
    return true;
  }

  bool _isReminderCooldownReady(CompanionStatus status, DateTime now) {
    if (status == CompanionStatus.postureDown) return true;
    final cooldown = _reminderCooldowns[status];
    final lastPlayedAt = _lastReminderPlayedAt[status];
    if (cooldown == null || lastPlayedAt == null) return true;
    return now.difference(lastPlayedAt) >= cooldown;
  }

  void _handlePostureReminderEpisode() {
    final now = DateTime.now();
    _postureRecoveryFrames = 0;
    if (!_isPostureReminderEpisodeActive) {
      _isPostureReminderEpisodeActive = true;
      _postureReminderEpisodeStartedAt = now;
      _postureReminderCount = 0;
    }

    if (_postureReminderCount >= _postureReminderMaxPerEpisode) return;
    final startedAt = _postureReminderEpisodeStartedAt ?? now;
    final shouldPlay =
        _postureReminderCount == 0 ||
        now.difference(startedAt) >= _postureReminderFollowUpDelay;
    if (!shouldPlay) return;

    _postureReminderCount += 1;
    debugPrint(
      'Posture reminder episode: count=$_postureReminderCount/'
      '$_postureReminderMaxPerEpisode',
    );
    _requestLocalReminder(CompanionStatus.postureDown);
  }

  void _updatePostureReminderRecovery(CompanionAnalysis analysis) {
    if (!_isPostureReminderEpisodeActive) return;

    final isClearlyRecovered =
        analysis.visionResult.hasPose &&
        analysis.postureDownResult.downFrameCount == 0;
    if (!isClearlyRecovered) {
      _postureRecoveryFrames = 0;
      return;
    }

    _postureRecoveryFrames += 1;
    if (_postureRecoveryFrames < _postureRecoveryFramesRequired) return;

    debugPrint('Posture reminder episode recovered');
    _resetPostureReminderEpisode();
  }

  void _resetPostureReminderEpisode() {
    _isPostureReminderEpisodeActive = false;
    _postureReminderEpisodeStartedAt = null;
    _postureReminderCount = 0;
    _postureRecoveryFrames = 0;
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
      if (played && status != CompanionStatus.postureDown) {
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
      case CompanionStatus.postureDown:
        return 4;
      case CompanionStatus.drowsy:
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

  String _voiceEventTypeForStatus(CompanionStatus status) {
    switch (status) {
      case CompanionStatus.attention:
        return 'vision.attention_warning';
      case CompanionStatus.fatigue:
        return 'vision.fatigue_detected';
      case CompanionStatus.distracted:
        return 'vision.distracted';
      case CompanionStatus.drowsy:
        return 'vision.drowsy';
      case CompanionStatus.postureDown:
        return 'vision.posture_down';
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
      case CompanionStatus.drowsy:
        return '快睡著了喔，坐直一點，醒一下。';
      case CompanionStatus.postureDown:
        return '你趴下了，先坐起來再繼續。';
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

  bool _shouldSpeakStatus(CompanionStatus status) {
    switch (status) {
      case CompanionStatus.attention:
      case CompanionStatus.fatigue:
      case CompanionStatus.distracted:
      case CompanionStatus.drowsy:
      case CompanionStatus.postureDown:
        return true;
      case CompanionStatus.normal:
      case CompanionStatus.userMissing:
        return false;
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
      case CompanionStatus.drowsy:
        return '偵測到低頭打瞌睡，建議抬頭或短暫休息。';
      case CompanionStatus.postureDown:
        return '偵測到疑似趴下睡覺，請確認目前狀態。';
      case CompanionStatus.userMissing:
        return '暫時沒有偵測到完整使用者。';
    }
  }

  Future<void> _showFatigueAlert({
    required double leftProbability,
    required double rightProbability,
    String? message,
  }) async {
    final alertMessage = message ?? "警告：偵測到連續閉眼，請立刻休息！";

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(alertMessage),
          backgroundColor: const Color(0xFFE85D75),
          duration: const Duration(seconds: 5),
        ),
      );
    }

    try {
      await _visionChannel.showToast(alertMessage);
    } catch (e) {
      debugPrint("Toast 呼叫失敗: $e");
    }
  }

  Future<void> _callNativeToast(String msg) async {
    try {
      await _visionChannel.showToast(msg);
    } catch (e) {
      debugPrint("手動 Toast 呼叫失敗: $e");
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

  void _applyVoiceInteraction(VoiceInteraction interaction) {
    _lastVoiceInteraction = interaction;
    _studySessionController.recordVoiceCommand(interaction.command);
    final previousPomodoroStatus = _pomodoroController.status;
    final actionResult = _pomodoroActionDispatcher.dispatch(
      command: interaction.command,
      controller: _pomodoroController,
      studySession: _studySessionController,
    );
    _recordPomodoroAction(
      interaction.command,
      previousStatus: previousPomodoroStatus,
      actionLabel: actionResult.response.actionLabel,
    );
    _companionMessage = actionResult.response.message;
    _lastVoiceResponseMessage = actionResult.response.message;
    _voiceMessagePinnedUntil = DateTime.now().add(_voiceMessageHoldDuration);

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
  }

  void _handlePomodoroControllerChanged() {
    final currentStatus = _pomodoroController.status;
    if (currentStatus == PomodoroStatus.completed &&
        _lastObservedPomodoroStatus != PomodoroStatus.completed) {
      _studySessionController.recordPomodoroCompleted();
      _companionMessage = '這輪專注完成了，先休息一下吧。';
      _lastVoiceResponseMessage = null;
      _voiceMessagePinnedUntil = null;
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
    _resetPostureReminderEpisode();
    _reminderEvidenceByStatus.clear();
    _lastReminderPlayedAt.clear();
    await _cameraController?.dispose();
    _detachFallbackVideoPositionListener();
    await _fallbackVideoController?.dispose();
    _cameraController = null;
    _fallbackVideoController = null;
    _fallbackVideoPath = null;
    _isUsingFallbackVideo = false;
    _companionController.reset();
    _visionEventTracker.reset();
    await _initializeCamera();
  }

  Future<void> _resetVisionCalibration() async {
    _companionController.reset();
    _resetPostureReminderEpisode();
    _reminderEvidenceByStatus.clear();
    _lastReminderPlayedAt.clear();
    _headOffsetSamples.clear();
    _closedEyeFrameCount = 0;
    _distractedFrameCount = 0;
    _postureDownFrameCount = 0;
    _headOffsetScore = null;
    _postureDownScore = null;
    _isHeadOffsetCalibrating = true;

    try {
      await _visionChannel.resetVision();
    } catch (e) {
      debugPrint("重設視覺校正失敗: $e");
    }
  }

  Color _getStatusColor() {
    switch (_companionStatus) {
      case CompanionStatus.fatigue:
        return const Color(0xFFE85D75);
      case CompanionStatus.attention:
      case CompanionStatus.distracted:
      case CompanionStatus.drowsy:
      case CompanionStatus.postureDown:
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
      case CompanionStatus.drowsy:
      case CompanionStatus.postureDown:
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
      case CompanionStatus.drowsy:
      case CompanionStatus.postureDown:
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
        _companionStatus == CompanionStatus.drowsy ||
        _companionStatus == CompanionStatus.postureDown) {
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
      case CompanionStatus.drowsy:
        return '快睡著啦，抬頭醒一下。';
      case CompanionStatus.postureDown:
        return '先別趴下，坐起來喘口氣。';
      case CompanionStatus.userMissing:
        return '我先待機，回來再陪你。';
    }
  }

  double get _companionMotionIntensity {
    switch (_companionStatus) {
      case CompanionStatus.normal:
        return 18;
      case CompanionStatus.attention:
      case CompanionStatus.distracted:
        return 8;
      case CompanionStatus.fatigue:
      case CompanionStatus.drowsy:
      case CompanionStatus.postureDown:
      case CompanionStatus.userMissing:
        return 2;
    }
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
      case CompanionStatus.drowsy:
        return "偵測到低頭打瞌睡，先抬頭休息一下。";
      case CompanionStatus.postureDown:
        return "偵測到趴下睡覺，先抬頭休息一下。";
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
      case CompanionStatus.drowsy:
        return '打瞌睡';
      case CompanionStatus.postureDown:
        return '趴下';
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
                          _showVoiceDemoPanel = !_showVoiceDemoPanel;
                          if (_showVoiceDemoPanel) _showDebugPanel = false;
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
                          if (_showDebugPanel) _showVoiceDemoPanel = false;
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
                        });
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
        _companionStatus != CompanionStatus.drowsy &&
        _companionStatus != CompanionStatus.postureDown) {
      return const SizedBox.shrink();
    }
    final isDistracted = _companionStatus == CompanionStatus.distracted;
    final isDrowsy = _companionStatus == CompanionStatus.drowsy;
    final isPostureDown = _companionStatus == CompanionStatus.postureDown;

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
                isPostureDown
                    ? "偵測到趴下睡覺，先抬頭休息一下。"
                    : isDrowsy
                    ? "偵測到低頭打瞌睡，先抬頭休息一下。"
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
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
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
      onHomeTap: () {
        setState(() {
          _showVoiceDemoPanel = false;
          _showDebugPanel = false;
          _showVisionSourcePreview = false;
        });
      },
      onStatisticsTap: () {
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
      bottom: 220,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
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
                    tooltip: '關閉',
                    onPressed: () {
                      setState(() => _showVoiceDemoPanel = false);
                    },
                    icon: const Icon(Icons.close_rounded),
                    color: const Color(0xFF63758C),
                    iconSize: 20,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildVoiceDemoChip("開始25", "final_start_pomodoro"),
                  _buildVoiceDemoChip("開始15", "final_start_custom_pomodoro"),
                  _buildVoiceDemoChip("暫停", "final_pause_timer"),
                  _buildVoiceDemoChip("繼續", "final_resume_timer"),
                  _buildVoiceDemoChip("中止", "final_stop_timer"),
                  _buildVoiceDemoChip("摘要", "final_summary_timer"),
                  _buildVoiceDemoChip("剩多久", "final_timer_status"),
                  _buildVoiceDemoChip("我累了", "final_report_tired"),
                  _buildVoiceDemoChip("分心", "final_report_distracted"),
                  _buildVoiceDemoChip("休息", "final_request_break"),
                  _buildVoiceDemoChip("確認", "final_low_confidence_pomodoro"),
                  _buildVoiceDemoChip("未知", "final_unknown_low_confidence"),
                ],
              ),
            ],
          ),
        ),
      ),
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
      bottom: _showVoiceDemoPanel || _showDebugPanel ? 390 : 190,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
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
                  Text(
                    timerText,
                    style: const TextStyle(
                      color: Color(0xFF2F7ED8),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
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
      bottom: 220,
      child: SafeArea(
        top: false,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "開發資訊",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF20324D),
                  ),
                ),
                const SizedBox(height: 10),
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
                        icon: const Icon(Icons.notifications_active_rounded),
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
                  _showVoiceDemoPanel = !_showVoiceDemoPanel;
                  if (_showVoiceDemoPanel) _showDebugPanel = false;
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
                  if (_showDebugPanel) _showVoiceDemoPanel = false;
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
    final controller = _cameraController;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _detectionTimer?.cancel();
      if (controller != null && controller.value.isInitialized) {
        controller.dispose();
        _cameraController = null;
      }
      _fallbackVideoController?.pause();
    } else if (state == AppLifecycleState.resumed) {
      if (_isUsingFallbackVideo) {
        _fallbackVideoController?.play();
        _startFallbackVideoDetectionLoop();
      } else {
        _initializeCamera();
      }
    }
  }

  Widget _buildCameraBackground() {
    return Stack(
      fit: StackFit.expand,
      children: [
        RiveAssetBackground(
          assetPath: 'assets/test2.riv',
          motionIntensity: _companionMotionIntensity,
        ),
        if (_showVisionSourcePreview) _buildVisionSourcePreview(),
      ],
    );
  }

  Widget _buildVisionSourcePreview() {
    final controller = _cameraController;
    if (controller != null && controller.value.isInitialized) {
      final previewSize = controller.value.previewSize;
      if (previewSize == null) {
        return CameraPreview(controller);
      }

      return ClipRect(
        child: SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: previewSize.height,
              height: previewSize.width,
              child: CameraPreview(controller),
            ),
          ),
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
    _userStatusCollapseTimer?.cancel();
    _idleBubbleTimer?.cancel();
    _idleBubbleHideTimer?.cancel();
    _breathingController.dispose();
    _cameraController?.dispose();
    _detachFallbackVideoPositionListener();
    _fallbackVideoController?.dispose();
    _completeVoicePlayback();
    _voicePlayerStateSubscription?.cancel();
    _voiceAudioPlayer.dispose();
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
          _buildGlassBottomNavigationBar(),
          _buildVoiceDialogPanel(),
          _buildVoiceDemoButtons(),
          _buildDebugPanel(),
        ],
      ),
    );
  }
}
