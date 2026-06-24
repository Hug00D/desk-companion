import 'dart:async';
import 'dart:io' as io;
import 'dart:ui' show ImageFilter;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_recognition_error.dart' as speech_error;
import 'package:speech_to_text/speech_recognition_result.dart' as speech_result;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:video_player/video_player.dart';

import '../ai/claude_intent_service.dart';
import '../ai/companion_ai_command_mapper.dart';
import '../ai/companion_ai_decision.dart';
import '../ai/pending_action_controller.dart';
import '../auth/auth_session.dart';
import '../companion/companion_response.dart';
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
import '../voice/voice_result.dart';
import '../widgets/glass_bottom_nav_bar.dart';
import '../widgets/rive_asset_background.dart';
import 'profile_detail_screen.dart';
import 'profile_hub_screen.dart';
import 'statistics_screen.dart';

class FaceDetectionScreen extends StatefulWidget {
  const FaceDetectionScreen({super.key});

  @override
  State<FaceDetectionScreen> createState() => _FaceDetectionScreenState();
}

class _FaceDetectionScreenState extends State<FaceDetectionScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  VideoPlayerController? _fallbackVideoController;

  Timer? _detectionTimer;
  Timer? _pomodoroTimer;
  Timer? _userStatusCollapseTimer;
  Timer? _idleBubbleTimer;
  Timer? _idleBubbleHideTimer;
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
  final stt.SpeechToText _speechToText = stt.SpeechToText();
  final ClaudeIntentService _claudeIntentService = ClaudeIntentService();
  final CompanionAiCommandMapper _aiCommandMapper =
      const CompanionAiCommandMapper();
  final PendingActionController _pendingActionController =
      PendingActionController();
  final PomodoroActionDispatcher _pomodoroActionDispatcher =
      const PomodoroActionDispatcher();
  final PomodoroController _pomodoroController = PomodoroController();
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
  bool _hasPose = false;

  bool _showDebugPanel = false;
  bool _showVoiceDemoPanel = false;
  bool _showVisionSourcePreview = false;
  bool _isUserStatusExpanded = false;
  bool _isAiThinking = false;
  bool _speechAvailable = false;
  bool _isSpeechInitializing = false;
  bool _isListeningToUser = false;
  bool _isSubmittingLiveVoice = false;
  String _liveVoiceText = '';
  String _speechStatus = '語音尚未啟動';
  String? _speechErrorMessage;
  String? _speechLocaleId = _defaultSpeechLocaleId;
  String? _lastSubmittedLiveVoiceText;

  static const Duration _voiceMessageHoldDuration = Duration(seconds: 5);
  static const Duration _idleChatterInterval = Duration(seconds: 35);
  static const Duration _idleChatterVisibleDuration = Duration(seconds: 7);
  static const bool _preferFallbackVideoForLocalTest = false;
  static const String _fallbackVideoAssetPath = 'assets/test_face.mp4';
  static const String _fallbackNativeVideoAssetName = 'test_face.mp4';
  static const String _fallbackVideoFileName = 'desk_companion_test_face.mp4';
  static const String _defaultSpeechLocaleId = 'zh_TW';
  static const List<String> _preferredSpeechLocaleIds = <String>[
    'zh_TW',
    'zh_Hant_TW',
    'cmn_Hant_TW',
    'zh_HK',
    'zh_CN',
    'cmn_Hans_CN',
  ];
  static const List<String> _idleChatterMessages = <String>[
    '今天節奏不錯，繼續保持。',
    '我在旁邊看著，有需要再叫我。',
    '專注條件良好，可以放心往下做。',
  ];

  int _closedEyeFrameCount = 0;
  int _distractedFrameCount = 0;
  int _postureDownFrameCount = 0;
  int _idleChatterIndex = 0;
  int _liveVoiceSessionCounter = 0;
  DateTime? _idleBubbleVisibleUntil;
  DateTime? _voiceMessagePinnedUntil;
  CompanionStatus _companionStatus = CompanionStatus.normal;
  String _fatigueLevel = CompanionStatus.normal.label;
  String _companionMessage = "目前狀態穩定，請保持節奏。";
  String? _lastVoiceResponseMessage;
  VoiceInteraction? _lastVoiceInteraction;
  VisionEventType _lastVisionEventType = VisionEventType.normal;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _breathingController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
      lowerBound: 0,
      upperBound: 1,
    )..repeat(reverse: true);
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
      final nativeVideoPath = await _copyNativeFallbackVideoToCache();
      final videoFile = nativeVideoPath != null
          ? io.File(nativeVideoPath)
          : await _copyFlutterFallbackVideoToCache(tempDir);

      final controller = VideoPlayerController.file(videoFile);
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      await _fallbackVideoController?.dispose();
      _fallbackVideoController = controller;
      _fallbackVideoPath = videoFile.path;
      _isUsingFallbackVideo = true;
      _isCameraInitializing = false;
      _cameraErrorMessage = null;
      _status = '本地測試模式：使用 test_face.mp4。';
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

  Future<String?> _copyNativeFallbackVideoToCache() async {
    try {
      return await _visionChannel.copyNativeAssetToCache(
        assetName: _fallbackNativeVideoAssetName,
        outputFileName: _fallbackVideoFileName,
      );
    } catch (e) {
      debugPrint('Android assets 測試影片讀取失敗，改用 Flutter assets: $e');
      return null;
    }
  }

  Future<io.File> _copyFlutterFallbackVideoToCache(io.Directory tempDir) async {
    final videoFile = io.File('${tempDir.path}/$_fallbackVideoFileName');
    final assetData = await rootBundle.load(_fallbackVideoAssetPath);
    await videoFile.writeAsBytes(
      assetData.buffer.asUint8List(
        assetData.offsetInBytes,
        assetData.lengthInBytes,
      ),
      flush: true,
    );
    return videoFile;
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
      final thumbnailBytes = await _visionChannel.extractVideoFrame(
        videoPath: videoPath,
        timeMs: controller.value.position.inMilliseconds,
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
    final previousCompanionStatus = _companionStatus;
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
    _hasPose = visionResult.hasPose;
    _closedEyeFrameCount = analysis.eyeResult.closedFrameCount;
    _distractedFrameCount = analysis.headOffsetResult.distractedFrameCount;
    _postureDownFrameCount = analysis.postureDownResult.downFrameCount;
    _companionStatus = analysis.status;
    if (analysis.status != previousCompanionStatus) {
      _syncBreathingPaceForStatus(analysis.status);
      if (analysis.status != CompanionStatus.normal) {
        _idleBubbleVisibleUntil = null;
      }
    }
    _fatigueLevel = analysis.status.label;
    _lastVisionEventType = trackingResult.event.type;
    if (!_isVoiceMessagePinned &&
        (analysis.status != previousCompanionStatus ||
            trackingResult.shouldUpdateMessage)) {
      _companionMessage = _messageForVisionTrackingResult(
        trackingResult,
        _messageForCompanionStatus(analysis.status),
      );
    }

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

  Future<void> _toggleLiveVoiceInput() async {
    if (_isListeningToUser) {
      await _stopLiveVoiceInput();
      return;
    }

    await _startLiveVoiceInput();
  }

  Future<bool> _ensureSpeechReady() async {
    if (_speechAvailable) return true;
    if (_isSpeechInitializing) return false;

    setState(() {
      _isSpeechInitializing = true;
      _speechErrorMessage = null;
      _speechStatus = '正在啟動語音辨識...';
    });

    try {
      final available = await _speechToText.initialize(
        onStatus: _handleSpeechStatus,
        onError: _handleSpeechError,
        options: [stt.SpeechToText.androidNoBluetooth],
      );
      if (!mounted) return available;

      String? localeId;
      if (available) {
        localeId = await _selectSpeechLocale();
      }

      if (!mounted) return available;
      setState(() {
        _speechAvailable = available;
        _speechLocaleId = localeId;
        _speechStatus = available
            ? '語音待命${localeId == null ? '' : ' ($localeId)'}'
            : '此裝置沒有可用的語音辨識服務';
      });
      return available;
    } catch (e) {
      if (mounted) {
        setState(() {
          _speechAvailable = false;
          _speechErrorMessage = e.toString();
          _speechStatus = '語音啟動失敗';
        });
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _isSpeechInitializing = false;
        });
      }
    }
  }

  Future<String?> _selectSpeechLocale() async {
    try {
      final locales = await _speechToText.locales();
      if (locales.isEmpty) return _defaultSpeechLocaleId;

      bool matches(stt.LocaleName locale, String expected) {
        final normalized = locale.localeId.toLowerCase().replaceAll('-', '_');
        final expectedNormalized = expected.toLowerCase().replaceAll('-', '_');
        return normalized == expectedNormalized;
      }

      for (final preferredLocaleId in _preferredSpeechLocaleIds) {
        for (final locale in locales) {
          if (matches(locale, preferredLocaleId)) return locale.localeId;
        }
      }
      for (final locale in locales) {
        final normalized = locale.localeId.toLowerCase().replaceAll('-', '_');
        if (normalized.startsWith('zh')) return locale.localeId;
      }
    } catch (e) {
      debugPrint('讀取語音語系失敗: $e');
    }
    return _defaultSpeechLocaleId;
  }

  Future<void> _startLiveVoiceInput() async {
    if (_isSubmittingLiveVoice || _isAiThinking) return;

    final ready = await _ensureSpeechReady();
    if (!mounted) return;
    if (!ready) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('目前無法啟動語音辨識，請確認麥克風權限與系統語音服務。'),
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    try {
      setState(() {
        _isListeningToUser = true;
        _liveVoiceText = '';
        _speechErrorMessage = null;
        _speechStatus = '正在聆聽...';
        _lastSubmittedLiveVoiceText = null;
      });

      await _speechToText.listen(
        onResult: _handleSpeechResult,
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: stt.ListenMode.confirmation,
          listenFor: const Duration(seconds: 12),
          pauseFor: const Duration(seconds: 3),
          localeId: _speechLocaleId,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isListeningToUser = false;
        _speechErrorMessage = e.toString();
        _speechStatus = '聆聽啟動失敗';
      });
    }
  }

  Future<void> _stopLiveVoiceInput() async {
    try {
      await _speechToText.stop();
    } catch (e) {
      debugPrint('停止語音辨識失敗: $e');
    }
    if (mounted) {
      setState(() {
        _isListeningToUser = false;
        _speechStatus = '語音待命';
      });
    }
  }

  void _handleSpeechStatus(String status) {
    if (!mounted) return;
    setState(() {
      _speechStatus = _speechStatusLabel(status);
      if (status == stt.SpeechToText.notListeningStatus ||
          status == stt.SpeechToText.doneStatus) {
        _isListeningToUser = false;
      } else if (status == stt.SpeechToText.listeningStatus) {
        _isListeningToUser = true;
      }
    });
  }

  void _handleSpeechError(speech_error.SpeechRecognitionError error) {
    if (!mounted) return;
    setState(() {
      _isListeningToUser = false;
      _speechErrorMessage = error.errorMsg;
      _speechStatus = error.permanent ? '語音錯誤，需要重新授權' : '語音辨識未成功';
    });
  }

  void _handleSpeechResult(speech_result.SpeechRecognitionResult result) {
    final text = result.recognizedWords.trim();
    final confidence = result.hasConfidenceRating && result.confidence > 0
        ? result.confidence
        : null;

    if (mounted) {
      setState(() {
        _liveVoiceText = text;
        if (result.finalResult) {
          _isListeningToUser = false;
          _speechStatus = text.isEmpty ? '沒有聽到可辨識內容' : '已收到語音';
        }
      });
    }

    if (!result.finalResult || text.isEmpty) return;
    if (_lastSubmittedLiveVoiceText == text) return;
    _lastSubmittedLiveVoiceText = text;
    unawaited(_submitLiveVoiceText(text, confidence));
  }

  Future<void> _submitLiveVoiceText(String text, double? confidence) async {
    if (_isSubmittingLiveVoice) return;
    if (text.trim().isEmpty) return;
    if (!mounted) return;

    setState(() {
      _isSubmittingLiveVoice = true;
      _speechStatus = '正在交給 AI 判斷...';
    });

    try {
      await _applyVoiceResult(_voiceResultFromLiveSpeech(text, confidence));
      if (mounted) {
        setState(() {
          _speechStatus = '語音待命';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmittingLiveVoice = false;
        });
      }
    }
  }

  VoiceRecognitionResult _voiceResultFromLiveSpeech(
    String text,
    double? confidence,
  ) {
    return VoiceRecognitionResult(
      sessionId: 'live_voice_${++_liveVoiceSessionCounter}',
      eventType: VoiceEventType.finalResult,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      transcript: text,
      formattedTranscript: text,
      isFinal: true,
      candidates: [VoiceCandidate(text: text, confidence: confidence)],
      audio: const VoiceAudioInfo(isSpeechDetected: true),
      language: VoiceLanguageInfo(tag: _speechLocaleId),
    );
  }

  String _speechStatusLabel(String status) {
    switch (status) {
      case stt.SpeechToText.listeningStatus:
        return '正在聆聽...';
      case stt.SpeechToText.notListeningStatus:
      case stt.SpeechToText.doneStatus:
        return '語音待命';
      default:
        return status;
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
      if (selectedResult == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("找不到語音測試資料: $caseId"),
            duration: const Duration(seconds: 4),
          ),
        );
        return;
      }

      await _applyVoiceResult(selectedResult);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("語音測試資料載入失敗: $e"),
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

  Future<void> _applyVoiceResult(VoiceRecognitionResult result) async {
    final pendingResolution = _pendingActionController.resolve(result.bestText);
    if (pendingResolution != null) {
      _applyPendingActionResolution(result, pendingResolution);
      return;
    }

    if (_pendingActionController.pending != null) {
      _pendingActionController.clear();
    }

    if (!result.isFinal || result.hasError) {
      _applyVoiceInteraction(_voiceInteractionController.handle(result));
      return;
    }

    if (!_claudeIntentService.isEnabled) {
      _applyVoiceInteraction(_voiceInteractionController.handle(result));
      return;
    }

    setState(() {
      _isAiThinking = true;
    });

    try {
      final aiDecision = await _claudeIntentService.decide(
        userText: result.bestText,
        context: ClaudeIntentContext(
          pomodoroStatus: _pomodoroController.status.name,
          pomodoroRemaining: _pomodoroController.formattedRemaining,
          companionStatus: _companionStatus.name,
          visionEvent: _lastVisionEventType.storageValue,
          hasFace: _hasFace,
          focusSummary: _studySessionController.buildSummary(
            _pomodoroController,
          ),
        ),
      );

      if (aiDecision == null) {
        _applyVoiceInteraction(_voiceInteractionController.handle(result));
        return;
      }

      _applyAiDecision(result, aiDecision);
    } catch (e) {
      debugPrint('Claude 意圖判斷失敗，改用本地規則: $e');
      _applyVoiceInteraction(_voiceInteractionController.handle(result));
    } finally {
      if (mounted) {
        setState(() {
          _isAiThinking = false;
        });
      }
    }
  }

  void _applyPendingActionResolution(
    VoiceRecognitionResult result,
    PendingActionResolution resolution,
  ) {
    if (resolution.type == PendingActionResolutionType.declined) {
      _showVoiceReply(
        result: result,
        command: VoiceCommand(
          type: VoiceCommandType.unknown,
          sourceText: result.bestText,
        ),
        message: '好，那我先不執行，陪你聊聊也可以。',
        actionLabel: 'decline_pending_action',
      );
      return;
    }

    final interaction = VoiceInteraction(
      result: result,
      command: resolution.action.command,
      response: CompanionResponse(
        source: CompanionResponseSource.voice,
        tone: CompanionResponseTone.action,
        message: resolution.action.confirmationText,
        actionLabel: 'confirm_pending_action',
      ),
    );
    _applyVoiceInteraction(interaction);
  }

  void _applyAiDecision(
    VoiceRecognitionResult result,
    CompanionAiDecision decision,
  ) {
    final command = _aiCommandMapper.toVoiceCommand(
      sourceText: result.bestText,
      decision: decision,
    );

    if (command == null ||
        decision.mode == CompanionAiMode.chat ||
        decision.mode == CompanionAiMode.clarify) {
      _showVoiceReply(
        result: result,
        command: VoiceCommand(
          type: VoiceCommandType.unknown,
          sourceText: result.bestText,
          confidence: decision.confidence,
        ),
        message: decision.chatReply.isNotEmpty
            ? decision.chatReply
            : '我聽到了，我們可以慢慢聊。',
        actionLabel: decision.mode == CompanionAiMode.clarify
            ? 'ai_ask_clarification'
            : 'ai_chat',
      );
      return;
    }

    final shouldConfirm =
        decision.needsConfirmation ||
        _aiCommandMapper.requiresConfirmation(command.type);
    if (shouldConfirm) {
      final confirmationText = decision.confirmationText.isNotEmpty
          ? decision.confirmationText
          : _aiCommandMapper.defaultConfirmationText(command);
      _pendingActionController.set(
        PendingCompanionAction(
          command: command,
          confirmationText: confirmationText,
        ),
      );
      _showVoiceReply(
        result: result,
        command: command,
        message: confirmationText,
        actionLabel: 'ai_confirm_${command.type.name}',
      );
      return;
    }

    _applyVoiceInteraction(
      VoiceInteraction(
        result: result,
        command: command,
        response: CompanionResponse(
          source: CompanionResponseSource.voice,
          tone: CompanionResponseTone.action,
          message: decision.chatReply,
          actionLabel: 'ai_${command.type.name}',
        ),
      ),
    );
  }

  void _showVoiceReply({
    required VoiceRecognitionResult result,
    required VoiceCommand command,
    required String message,
    String? actionLabel,
  }) {
    _lastVoiceInteraction = VoiceInteraction(
      result: result,
      command: command,
      response: CompanionResponse(
        source: CompanionResponseSource.voice,
        tone: CompanionResponseTone.supportive,
        message: message,
        actionLabel: actionLabel,
      ),
    );
    _companionMessage = message;
    _lastVoiceResponseMessage = message;
    _voiceMessagePinnedUntil = DateTime.now().add(_voiceMessageHoldDuration);

    if (mounted) {
      setState(() {});
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

    if (actionResult.shouldStopTimer) {
      _pomodoroTimer?.cancel();
    }

    if (actionResult.shouldStartTimer) {
      _startPomodoroTicker();
    }

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

  void _startPomodoroTicker() {
    _pomodoroTimer?.cancel();
    _pomodoroTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      setState(() {
        _pomodoroController.tick();
      });

      if (_pomodoroController.status == PomodoroStatus.completed) {
        timer.cancel();
        _studySessionController.recordPomodoroCompleted();
        _companionMessage = "這輪專注時間結束了，休息一下吧。";
        _lastVoiceResponseMessage = null;
        _voiceMessagePinnedUntil = null;
        if (mounted) setState(() {});
      }
    });
  }

  bool get _isVoiceMessagePinned {
    final pinnedUntil = _voiceMessagePinnedUntil;
    return pinnedUntil != null && DateTime.now().isBefore(pinnedUntil);
  }

  Future<void> _restartCamera() async {
    _detectionTimer?.cancel();
    await _cameraController?.dispose();
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
    if (_isVoiceMessagePinned) return true;
    if (_companionStatus != CompanionStatus.normal) return true;

    final visibleUntil = _idleBubbleVisibleUntil;
    return visibleUntil != null && DateTime.now().isBefore(visibleUntil);
  }

  String get _companionBubbleMessage {
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
                      title: '語音輸入',
                      subtitle: '即時麥克風與開發測試案例。',
                      isActive: _showVoiceDemoPanel,
                      onTap: () {
                        Navigator.pop(context);
                        final nextValue = !_showVoiceDemoPanel;
                        if (!nextValue && _isListeningToUser) {
                          unawaited(_stopLiveVoiceInput());
                        }
                        setState(() {
                          _showVoiceDemoPanel = nextValue;
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
                        if (_isListeningToUser) {
                          unawaited(_stopLiveVoiceInput());
                        }
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
        if (_isListeningToUser) {
          unawaited(_stopLiveVoiceInput());
        }
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
      onTasksTap: () => _showBottomNavComingSoon('任務'),
      onSettingsTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const ProfileHubScreen()),
        );
      },
    );
  }

  void _showBottomNavComingSoon(String title) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title 功能之後會接上正式頁面。'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
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
                      '語音輸入',
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
                      if (_isListeningToUser) {
                        unawaited(_stopLiveVoiceInput());
                      }
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
              _buildLiveVoiceInputCard(),
              const SizedBox(height: 10),
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

  Widget _buildLiveVoiceInputCard() {
    final isBusy =
        _isSpeechInitializing || _isSubmittingLiveVoice || _isAiThinking;
    final canToggle = _isListeningToUser || !isBusy;
    final buttonLabel = _isListeningToUser
        ? '停止聆聽'
        : _isSubmittingLiveVoice || _isAiThinking
        ? '判斷中'
        : '開始聆聽';
    final icon = _isListeningToUser
        ? Icons.stop_rounded
        : _isSubmittingLiveVoice || _isAiThinking
        ? Icons.hourglass_top_rounded
        : Icons.mic_rounded;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6FBFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD8EEF8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: canToggle ? _toggleLiveVoiceInput : null,
                  icon: Icon(icon, size: 18),
                  label: Text(buttonLabel),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isListeningToUser
                        ? const Color(0xFFE85D75)
                        : const Color(0xFF57BEEB),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: _isListeningToUser
                      ? const Color(0xFFE85D75)
                      : _speechAvailable
                      ? const Color(0xFF37B26C)
                      : const Color(0xFF9FB0C2),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _speechStatus,
            style: const TextStyle(
              color: Color(0xFF3F607D),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (_liveVoiceText.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '目前聽到：$_liveVoiceText',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF31465F),
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
          if (_speechErrorMessage != null) ...[
            const SizedBox(height: 6),
            Text(
              _speechErrorMessage!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFE85D75),
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (_lastVoiceResponseMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              '回覆：$_lastVoiceResponseMessage',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF20324D),
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVoiceDemoChip(String label, String caseId) {
    final isBusy =
        _isVoiceDemoLoading ||
        _isAiThinking ||
        _isSubmittingLiveVoice ||
        _isListeningToUser;
    return SizedBox(
      height: 36,
      child: ElevatedButton(
        onPressed: isBusy ? null : () => _runVoiceDemo(caseId),
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
        child: isBusy
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
    if (_showVoiceDemoPanel) return const SizedBox.shrink();
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
                      "語音輸入",
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
                  _buildVoiceMetaChip(
                    _claudeIntentService.isEnabled
                        ? "Claude: 啟用"
                        : "Claude: fallback",
                  ),
                  _buildVoiceMetaChip("視覺狀態: $_fatigueLevel"),
                  _buildVoiceMetaChip("畫面: ${_hasFace ? "有人臉" : "未見人臉"}"),
                  _buildVoiceMetaChip("Pose: ${_hasPose ? "有" : "無"}"),
                  _buildVoiceMetaChip(
                    _isListeningToUser ? "Mic: 聆聽中" : "Mic: 待命",
                  ),
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
              label: '語音',
              isActive: _showVoiceDemoPanel,
              onTap: () {
                final nextValue = !_showVoiceDemoPanel;
                if (!nextValue && _isListeningToUser) {
                  unawaited(_stopLiveVoiceInput());
                }
                setState(() {
                  _showVoiceDemoPanel = nextValue;
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
                if (_isListeningToUser) {
                  unawaited(_stopLiveVoiceInput());
                }
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
    _pomodoroTimer?.cancel();
    _userStatusCollapseTimer?.cancel();
    _idleBubbleTimer?.cancel();
    _idleBubbleHideTimer?.cancel();
    _speechToText.cancel();
    _breathingController.dispose();
    _cameraController?.dispose();
    _fallbackVideoController?.dispose();
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
