import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rive/rive.dart' as rv; // 使用 rv 避免命名空間衝突
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../companion/companion_controller.dart';
import '../companion/companion_response_builder.dart';
import '../focus/pomodoro_action_dispatcher.dart';
import '../focus/pomodoro_controller.dart';
import '../vision/companion_state_evaluator.dart';
import '../vision/vision_channel.dart';
import '../vision/vision_result.dart';
import '../voice/mock_voice_result_loader.dart';
import '../voice/voice_interaction_controller.dart';

class FaceDetectionScreen extends StatefulWidget {
  const FaceDetectionScreen({super.key});

  @override
  State<FaceDetectionScreen> createState() => _FaceDetectionScreenState();
}

class _FaceDetectionScreenState extends State<FaceDetectionScreen> {
  late VideoPlayerController _controller;

  Timer? _detectionTimer;
  Timer? _pomodoroTimer;
  bool _isProcessing = false;
  bool _isVoiceDemoLoading = false;
  String _status = "等待辨識...";
  String? _tempVideoPath;
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

  double? _leftEyeOpenValue;
  double? _rightEyeOpenValue;
  bool _hasFace = false;

  bool _showDebugPanel = false;

  static const Duration _alertCooldown = Duration(seconds: 3);
  static const Duration _voiceMessageHoldDuration = Duration(seconds: 5);

  int _closedEyeFrameCount = 0;
  DateTime? _lastAlertTime;
  DateTime? _voiceMessagePinnedUntil;
  CompanionStatus _companionStatus = CompanionStatus.normal;
  String _fatigueLevel = CompanionStatus.normal.label;
  String _companionMessage = "目前狀態穩定，請保持節奏。";
  String? _lastVoiceResponseMessage;
  VoiceInteraction? _lastVoiceInteraction;

  @override
  void initState() {
    super.initState();

    _controller = VideoPlayerController.asset('assets/test_face.mp4')
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {});
        _controller.play();
        _controller.setLooping(true);
      });

    _detectionTimer = Timer.periodic(const Duration(milliseconds: 200), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_controller.value.isInitialized && !_isProcessing) {
        _detectFaceFromVideo();
      }
    });
  }

  // --- 核心偵測函式 ---
  Future<void> _detectFaceFromVideo() async {
    if (_isProcessing || !_controller.value.isInitialized) return;
    _isProcessing = true;

    String? thumbnailPath;

    try {
      if (_tempVideoPath == null) {
        final byteData = await rootBundle.load('assets/test_face.mp4');
        final directory = await getTemporaryDirectory();
        final file = io.File('${directory.path}/temp_video.mp4');
        await file.writeAsBytes(
          byteData.buffer.asUint8List(
            byteData.offsetInBytes,
            byteData.lengthInBytes,
          ),
        );
        _tempVideoPath = file.path;
      }

      thumbnailPath = await VideoThumbnail.thumbnailFile(
        video: _tempVideoPath!,
        thumbnailPath: (await getTemporaryDirectory()).path,
        imageFormat: ImageFormat.JPEG,
        timeMs: _controller.value.position.inMilliseconds,
        quality: 20,
      );

      if (thumbnailPath == null) return;

      final imageFile = io.File(thumbnailPath);
      final Uint8List imageBytes = await imageFile.readAsBytes();

      final visionResult = await _visionChannel.analyzeFrame(imageBytes);

      _handleVisionResult(visionResult);
    } catch (e) {
      debugPrint("辨識錯誤: $e");
    } finally {
      _isProcessing = false;
      if (thumbnailPath != null) {
        final file = io.File(thumbnailPath);
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
    debugPrint(
      'Vision data: '
      'hasFace=${visionResult.hasFace}, '
      'leftEye=${visionResult.leftEyeOpen?.toStringAsFixed(3) ?? 'N/A'}, '
      'rightEye=${visionResult.rightEyeOpen?.toStringAsFixed(3) ?? 'N/A'}, '
      'headYaw=${_formatRawValue(visionResult.raw['headYaw'])}, '
      'headPitch=${_formatRawValue(visionResult.raw['headPitch'])}, '
      'hasPose=${visionResult.hasPose}, '
      'shoulderWidth=${visionResult.shoulderWidth?.toStringAsFixed(1) ?? 'N/A'}, '
      'ls=(${_formatRawValue(visionResult.raw['lsX'])}, ${_formatRawValue(visionResult.raw['lsY'])}), '
      'rs=(${_formatRawValue(visionResult.raw['rsX'])}, ${_formatRawValue(visionResult.raw['rsY'])})',
    );

    final analysis = _companionController.analyze(visionResult);
    final response = _responseBuilder.fromVision(analysis);

    _leftEyeOpenValue = visionResult.leftEyeOpen;
    _rightEyeOpenValue = visionResult.rightEyeOpen;
    _hasFace = visionResult.hasFace;
    _closedEyeFrameCount = analysis.eyeResult.closedFrameCount;
    _companionStatus = analysis.status;
    _fatigueLevel = analysis.status.label;
    if (!_isVoiceMessagePinned) {
      _companionMessage = response.message;
    }

    if (_companionStatus == CompanionStatus.fatigue &&
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
            "寬度: ${visionResult.shoulderWidth?.toStringAsFixed(1) ?? 'N/A'} px\n"
            "左眼: ${_leftEyeOpenValue?.toStringAsFixed(2) ?? 'N/A'} 右眼: ${_rightEyeOpenValue?.toStringAsFixed(2) ?? 'N/A'}\n"
            "狀態: $_fatigueLevel";
      });
    }
  }

  Future<void> _showFatigueAlert({
    required double leftProbability,
    required double rightProbability,
    String? message,
  }) async {
    final now = DateTime.now();
    if (_lastAlertTime != null &&
        now.difference(_lastAlertTime!) < _alertCooldown) {
      return;
    }
    _lastAlertTime = now;

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
    final actionResult = _pomodoroActionDispatcher.dispatch(
      command: interaction.command,
      controller: _pomodoroController,
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

  Future<void> _restartVideo() async {
    if (!_controller.value.isInitialized) return;
    await _controller.seekTo(Duration.zero);
    await _controller.play();
  }

  Color _getStatusColor() {
    switch (_companionStatus) {
      case CompanionStatus.fatigue:
        return const Color(0xFFE85D75);
      case CompanionStatus.attention:
        return const Color(0xFFFFB648);
      case CompanionStatus.normal:
      case CompanionStatus.userMissing:
        return const Color(0xFF68C7F2);
    }
  }

  String _getCompanionMessage() {
    return _companionMessage;
  }

  String _formatEyeValue(double? value) {
    if (value == null) return "--";
    return value.toStringAsFixed(2);
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
            color: color.withOpacity(0.45),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }

  Widget _buildAttentionBanner() {
    if (_companionStatus != CompanionStatus.attention) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 96,
      left: 18,
      right: 18,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.92),
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
          children: const [
            Icon(Icons.visibility_rounded, color: Color(0xFFFFA94D)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                "偵測到短時間連續閉眼，請留意目前狀態。",
                style: TextStyle(
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
          color: Colors.white.withOpacity(0.95),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: const Color(0xFFFFEEF1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.health_and_safety_rounded,
                color: Color(0xFFE85D75),
                size: 34,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "疲勞提醒",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF20324D),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
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
            color: Colors.white.withOpacity(0.88),
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
    return Positioned(
      top: 74,
      left: 18,
      right: 18,
      child: SafeArea(
        bottom: false,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildVoiceDemoChip("開始25", "final_start_pomodoro"),
            _buildVoiceDemoChip("開始15", "final_start_custom_pomodoro"),
            _buildVoiceDemoChip("暫停", "final_pause_timer"),
            _buildVoiceDemoChip("繼續", "final_resume_timer"),
            _buildVoiceDemoChip("中止", "final_stop_timer"),
            _buildVoiceDemoChip("摘要", "final_summary_timer"),
            _buildVoiceDemoChip("未知", "final_unknown_low_confidence"),
          ],
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
          backgroundColor: Colors.white.withOpacity(0.18),
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.white.withOpacity(0.24)),
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
      bottom: 190,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.92),
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
      bottom: 150,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.94),
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
                Text("連續閉眼次數：$_closedEyeFrameCount"),
                Text("是否偵測到人臉：${_hasFace ? "是" : "否"}"),
                Text("目前狀態：$_fatigueLevel"),
                const SizedBox(height: 10),
                Text(_status),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _restartVideo,
                        icon: const Icon(Icons.replay_rounded),
                        label: const Text("重新播放"),
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
                        onPressed: () => _callNativeToast("手動觸發辨識結果！"),
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDebugToggleButton() {
    return Positioned(
      top: 18,
      right: 18,
      child: SafeArea(
        bottom: false,
        child: GestureDetector(
          onLongPress: () {
            setState(() {
              _showDebugPanel = !_showDebugPanel;
            });
          },
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.24)),
            ),
            child: const Icon(
              Icons.tune_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _detectionTimer?.cancel();
    _pomodoroTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color overlayColor = _companionStatus == CompanionStatus.fatigue
        ? const Color(0x66E85D75)
        : _companionStatus == CompanionStatus.attention
        ? const Color(0x33FFB648)
        : const Color(0x220D3B66);

    return Scaffold(
      backgroundColor: const Color(0xFFF5FBFF),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Full-screen video
          // 換成你的 Rive 角色
          SizedBox.expand(
            // 把 const 刪掉
            child: rv.RiveAnimation.asset('assets/test.riv', fit: BoxFit.cover),
          ),

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

          // Top title
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withOpacity(0.22)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Color(0xFF79D2F5),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          "Desk Companion",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

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
