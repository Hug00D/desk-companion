import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:rive/rive.dart' as rv;

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
import 'profile_hub_screen.dart';

class FaceDetectionScreen extends StatefulWidget {
  const FaceDetectionScreen({super.key});

  @override
  State<FaceDetectionScreen> createState() => _FaceDetectionScreenState();
}

class _FaceDetectionScreenState extends State<FaceDetectionScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  CameraController? _cameraController;

  Timer? _detectionTimer;
  Timer? _pomodoroTimer;
  Timer? _userStatusCollapseTimer;
  late final AnimationController _breathingController;
  bool _isProcessing = false;
  bool _isCameraInitializing = true;
  bool _isVoiceDemoLoading = false;
  String _status = "等待辨識...";
  String? _cameraErrorMessage;
  final VisionChannel _visionChannel = const VisionChannel();
  final CompanionController _companionController = CompanionController();
  final CompanionResponseBuilder _responseBuilder =
      const CompanionResponseBuilder();
  final MockVoiceResultLoader _mockVoiceResultLoader =
      const MockVoiceResultLoader(assetPath: 'assets/mock/voice_intents.json');
  final VoiceInteractionController _voiceInteractionController =
      const VoiceInteractionController();
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
  bool _isHeadOffsetCalibrating = false;
  final List<double> _headOffsetSamples = <double>[];
  bool _hasFace = false;

  bool _showDebugPanel = false;
  bool _showVoiceDemoPanel = false;
  bool _isUserStatusExpanded = false;

  static const Duration _voiceMessageHoldDuration = Duration(seconds: 5);

  int _closedEyeFrameCount = 0;
  int _distractedFrameCount = 0;
  int _postureDownFrameCount = 0;
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
      duration: const Duration(milliseconds: 1500),
      lowerBound: 0,
      upperBound: 1,
    )..repeat(reverse: true);
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
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
      _isCameraInitializing = false;
      _status = "相機已啟動，等待辨識...";
      _startCameraDetectionLoop();
      setState(() {});
    } catch (e) {
      if (!mounted) return;
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
    _companionStatus = analysis.status;
    _fatigueLevel = analysis.status.label;
    _lastVisionEventType = trackingResult.event.type;
    if (!_isVoiceMessagePinned && trackingResult.shouldUpdateMessage) {
      _companionMessage = _messageForVisionTrackingResult(
        trackingResult,
        response.message,
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
    _cameraController = null;
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

  String _getCompanionMessage() {
    return _companionMessage;
  }

  String get _displayName {
    final email = _authSession.email;
    if (email == null || email.isEmpty) return 'Reader';
    return email.split('@').first;
  }

  String get _timerHudText {
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
        height: 96,
        width: 300,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _buildHudChip(_statusHudText, _getStatusColor()),
            _buildHudChip('$_todayFocusHudText 專注', Colors.white),
            _buildHudChip(_timerHudText, const Color(0xFF79D2F5)),
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
      message: 'AI 偏好設定',
      child: GestureDetector(
        onTap: _showAiPreferenceSheet,
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
        MaterialPageRoute(builder: (context) => const ProfileHubScreen()),
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
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _detectionTimer?.cancel();
      controller.dispose();
      _cameraController = null;
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Widget _buildCameraBackground() {
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

    return Container(
      color: const Color(0xFF10283D),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const rv.RiveAnimation.asset('assets/test.riv', fit: BoxFit.cover),
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
    _breathingController.dispose();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWarmWarning =
        _companionStatus == CompanionStatus.attention ||
        _companionStatus == CompanionStatus.distracted ||
        _companionStatus == CompanionStatus.drowsy ||
        _companionStatus == CompanionStatus.postureDown;
    final Color overlayColor = _companionStatus == CompanionStatus.fatigue
        ? const Color(0x66E85D75)
        : isWarmWarning
        ? const Color(0x33FFB648)
        : const Color(0x220D3B66);

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
                  overlayColor,
                  const Color(0x55F4FBFF),
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),

          _buildTopHud(),

          // Status banner and fatigue card
          _buildAttentionBanner(),
          if (_companionStatus == CompanionStatus.fatigue)
            const Positioned.fill(child: ColoredBox(color: Color(0x22E85D75))),
          Positioned.fill(
            child: SafeArea(
              child: Column(
                children: [
                  const Spacer(),
                  if (_companionStatus == CompanionStatus.fatigue)
                    _buildFatigueAlertCard(),
                  const Spacer(),
                ],
              ),
            ),
          ),
          _buildBottomCompanionPanel(),
          _buildVoiceDialogPanel(),
          _buildVoiceDemoButtons(),
          _buildDebugPanel(),
          _buildDebugToggleButton(),
        ],
      ),
    );
  }
}
