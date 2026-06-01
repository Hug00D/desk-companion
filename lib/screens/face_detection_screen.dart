import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rive/rive.dart' as rv;
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../companion/companion_controller.dart';
import '../vision/companion_state_evaluator.dart';
import '../vision/vision_channel.dart';
import '../vision/vision_result.dart';

class FaceDetectionScreen extends StatefulWidget {
  const FaceDetectionScreen({super.key});

  @override
  State<FaceDetectionScreen> createState() => _FaceDetectionScreenState();
}

class _FaceDetectionScreenState extends State<FaceDetectionScreen> {
  static const String _testVideoAsset = 'assets/test.mp4';

  late VideoPlayerController _controller;

  Timer? _detectionTimer;
  bool _isProcessing = false;
  String _status = "等待辨識...";
  String? _tempVideoPath;
  final VisionChannel _visionChannel = const VisionChannel();
  final CompanionController _companionController = CompanionController();

  double? _leftEyeOpenValue;
  double? _rightEyeOpenValue;
  double? _headYaw;
  double? _headPitch;
  double? _headOffsetScore;
  double? _postureDownScore;
  double? _poseNoseY;
  int? _lastAnalyzedVideoMs;
  bool _isHeadOffsetCalibrating = false;
  final List<double> _headOffsetSamples = <double>[];
  bool _hasFace = false;

  bool _showDebugPanel = false;
  bool _showVideoPreview = true;

  static const Duration _alertCooldown = Duration(seconds: 3);

  int _closedEyeFrameCount = 0;
  int _distractedFrameCount = 0;
  int _postureDownFrameCount = 0;
  DateTime? _lastAlertTime;
  CompanionStatus _companionStatus = CompanionStatus.normal;
  String _fatigueLevel = CompanionStatus.normal.label;

  @override
  void initState() {
    super.initState();

    _controller = VideoPlayerController.asset(_testVideoAsset)
      ..initialize().then((_) async {
        if (!mounted) return;
        setState(() {});
        await _resetVisionCalibration();
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

  Future<void> _detectFaceFromVideo() async {
    if (_isProcessing || !_controller.value.isInitialized) return;
    _isProcessing = true;

    try {
      if (_tempVideoPath == null) {
        final byteData = await rootBundle.load(_testVideoAsset);
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

      final positionMs = _controller.value.position.inMilliseconds;

      final imageBytes = await VideoThumbnail.thumbnailData(
        video: _tempVideoPath!,
        imageFormat: ImageFormat.JPEG,
        timeMs: positionMs,
        quality: 20,
      );

      if (imageBytes == null) return;

      _lastAnalyzedVideoMs = positionMs;
      final visionResult = await _visionChannel.analyzeFrame(imageBytes);

      _handleVisionResult(visionResult);
    } catch (e) {
      debugPrint("辨識錯誤: $e");
    } finally {
      _isProcessing = false;
    }
  }

  void _handleVisionResult(VisionResult visionResult) {
    final analysis = _companionController.analyze(visionResult);

    debugPrint(
      'Vision data: '
      'videoMs=${_lastAnalyzedVideoMs ?? -1}, '
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

    if (_companionStatus == CompanionStatus.fatigue &&
        _leftEyeOpenValue != null &&
        _rightEyeOpenValue != null) {
      _showFatigueAlert(
        leftProbability: _leftEyeOpenValue!,
        rightProbability: _rightEyeOpenValue!,
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

  Future<void> _showFatigueAlert({
    required double leftProbability,
    required double rightProbability,
  }) async {
    final now = DateTime.now();
    if (_lastAlertTime != null &&
        now.difference(_lastAlertTime!) < _alertCooldown) {
      return;
    }
    _lastAlertTime = now;

    const message = "警告：偵測到連續閉眼，請先休息一下。";

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(message),
          backgroundColor: Color(0xFFE85D75),
          duration: Duration(seconds: 2),
        ),
      );
    }

    try {
      await _visionChannel.showToast(message);
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

  Future<void> _restartVideo() async {
    if (!_controller.value.isInitialized) return;
    await _resetVisionCalibration();
    await _controller.seekTo(Duration.zero);
    await _controller.play();
  }

  Future<void> _resetVisionCalibration() async {
    _companionController.reset();
    _headOffsetSamples.clear();
    _lastAnalyzedVideoMs = null;
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
      case CompanionStatus.tooClose:
        return const Color(0xFFFFB648);
      case CompanionStatus.normal:
      case CompanionStatus.userMissing:
        return const Color(0xFF68C7F2);
    }
  }

  String _getCompanionMessage() {
    if (!_hasFace &&
        _companionStatus != CompanionStatus.postureDown &&
        _companionStatus != CompanionStatus.distracted &&
        _companionStatus != CompanionStatus.drowsy) {
      return "尚未偵測到使用者，請確認畫面與光線。";
    }

    switch (_companionStatus) {
      case CompanionStatus.fatigue:
        return "偵測到持續閉眼，建議先休息一下。";
      case CompanionStatus.attention:
        return "似乎有些疲倦了，記得留意狀態。";
      case CompanionStatus.distracted:
        return "視線偏離了一段時間，先把注意力帶回螢幕吧。";
      case CompanionStatus.drowsy:
        return "偵測到低頭打瞌睡，先抬頭休息一下。";
      case CompanionStatus.postureDown:
        return "偵測到趴下睡覺，先抬頭休息一下。";
      case CompanionStatus.tooClose:
        return "你靠得太近了，請調整坐姿保護眼睛。";
      case CompanionStatus.normal:
      case CompanionStatus.userMissing:
        return "目前狀態穩定，請保持節奏。";
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

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
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
      top: _showVideoPreview ? 316 : 96,
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
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
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

  Widget _buildVideoPreviewPanel() {
    if (!_showVideoPreview) return const SizedBox.shrink();

    return Positioned(
      top: 74,
      left: 18,
      right: 18,
      child: SafeArea(
        bottom: false,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(18),
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
                  const Icon(
                    Icons.movie_filter_rounded,
                    color: Color(0xFF2F7ED8),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      "測試影片同步預覽",
                      style: TextStyle(
                        color: Color(0xFF20324D),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: "隱藏影片",
                    onPressed: () {
                      setState(() {
                        _showVideoPreview = false;
                      });
                    },
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ],
              ),
              if (_controller.value.isInitialized)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      AspectRatio(
                        aspectRatio: _controller.value.aspectRatio,
                        child: VideoPlayer(_controller),
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        color: Colors.black.withValues(alpha: 0.45),
                        child: Row(
                          children: [
                            Icon(
                              _controller.value.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "${_formatDuration(_controller.value.position)} / "
                              "${_formatDuration(_controller.value.duration)}",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              "趴下 ${_formatScore(_postureDownScore)}",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              else
                const SizedBox(
                  height: 140,
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _printHeadOffsetStats();
    _detectionTimer?.cancel();
    _controller.dispose();
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
          SizedBox.expand(
            child: rv.RiveAnimation.asset('assets/test.riv', fit: BoxFit.cover),
          ),
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
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
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
          _buildVideoPreviewPanel(),
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
          _buildDebugPanel(),
          if (!_showVideoPreview)
            Positioned(
              top: 74,
              right: 18,
              child: SafeArea(
                bottom: false,
                child: FloatingActionButton.small(
                  heroTag: "show-video-preview",
                  tooltip: "顯示影片",
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF2F7ED8),
                  onPressed: () {
                    setState(() {
                      _showVideoPreview = true;
                    });
                  },
                  child: const Icon(Icons.movie_filter_rounded),
                ),
              ),
            ),
          _buildDebugToggleButton(),
        ],
      ),
    );
  }
}
