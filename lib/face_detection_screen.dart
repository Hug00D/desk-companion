import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rive/rive.dart' as rv;
import 'vision/pose_calculator.dart';
import 'dart:io' as io;

class FaceDetectionScreen extends StatefulWidget {
  const FaceDetectionScreen({super.key});

  @override
  State<FaceDetectionScreen> createState() => _FaceDetectionScreenState();
}

class _FaceDetectionScreenState extends State<FaceDetectionScreen> {
  late VideoPlayerController _controller;
  static const platform = MethodChannel('com.example.desk_companion/cv_channel');

  Timer? _detectionTimer;
  bool _isProcessing = false;
  String _status = "等待辨識...";
  String? _tempVideoPath;

  double? _leftEyeOpenValue;
  double? _rightEyeOpenValue;
  double? _leftEyeProbabilityValue;
  double? _rightEyeProbabilityValue;
  String _eyeMetricMode = "WAITING";
  bool _hasFace = false;

  bool _showDebugPanel = false;
  bool _hasHand = false;
  String _detectedGesture = "none";

  // EAR 數值通常越小代表眼睛越閉；ML Kit probability 則越小代表越閉。
  static const double _earClosedThreshold = 0.18;
  static const double _probabilityClosedThreshold = 0.2;
  static const int _attentionClosedFrames = 2;
  static const int _fatigueClosedFrames = 5;
  static const int _victoryGestureFrames = 2;
  static const Duration _alertCooldown = Duration(seconds: 3);
  static const Duration _gestureAlertCooldown = Duration(seconds: 4);

  int _closedEyeFrameCount = 0;
  int _victoryGestureFrameCount = 0;
  DateTime? _lastAlertTime;
  DateTime? _lastGestureAlertTime;
  String _fatigueLevel = "正常";

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

    _detectionTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
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
        debugPrint("影片已成功搬移至: $_tempVideoPath");
      }

      thumbnailPath = await VideoThumbnail.thumbnailFile(
        video: _tempVideoPath!,
        thumbnailPath: (await getTemporaryDirectory()).path,
        imageFormat: ImageFormat.JPEG,
        timeMs: _controller.value.position.inMilliseconds,
        quality: 35,
      );

      if (thumbnailPath == null) {
        if (mounted) {
          setState(() => _status = "抽幀失敗：無法取得影片畫面");
        }
        return;
      }

      final imageFile = io.File(thumbnailPath);
      final Uint8List imageBytes = await imageFile.readAsBytes();
      final dynamic result = await platform.invokeMethod('analyzeFrame', imageBytes);

      if (result != null) {
        double? shoulderWidth;

        if (result['hasPose'] == true) {
          shoulderWidth = PoseCalculator.getWidth(
            (result['lsX'] as num).toDouble(),
            (result['lsY'] as num).toDouble(),
            (result['rsX'] as num).toDouble(),
            (result['rsY'] as num).toDouble(),
          );
        }

        _updateGestureState(result);

        if (result['hasFace'] == true) {
          _hasFace = true;
          _eyeMetricMode = (result['eyeMetricMode'] as String?) ?? "UNKNOWN";

          final leftEar = (result['leftEAR'] as num?)?.toDouble();
          final rightEar = (result['rightEAR'] as num?)?.toDouble();
          final leftProbability =
              (result['leftEyeProbability'] as num?)?.toDouble() ??
                  (result['leftEye'] as num?)?.toDouble();
          final rightProbability =
              (result['rightEyeProbability'] as num?)?.toDouble() ??
                  (result['rightEye'] as num?)?.toDouble();

          _leftEyeProbabilityValue = leftProbability;
          _rightEyeProbabilityValue = rightProbability;

          final bool hasValidEar =
              leftEar != null && rightEar != null && leftEar > 0 && rightEar > 0;

          if (hasValidEar) {
            _leftEyeOpenValue = leftEar;
            _rightEyeOpenValue = rightEar;
          } else {
            _leftEyeOpenValue = leftProbability;
            _rightEyeOpenValue = rightProbability;
          }

          final bool bothEyesClosed = hasValidEar
              ? leftEar < _earClosedThreshold && rightEar < _earClosedThreshold
              : leftProbability != null &&
                  rightProbability != null &&
                  leftProbability < _probabilityClosedThreshold &&
                  rightProbability < _probabilityClosedThreshold;

          if (bothEyesClosed) {
            _closedEyeFrameCount++;
          } else {
            _closedEyeFrameCount = 0;
          }

          _updateFatigueLevel(shoulderWidth);

          if (_closedEyeFrameCount >= _fatigueClosedFrames) {
            _showFatigueAlert();
          }
        } else {
          _hasFace = false;
          _eyeMetricMode = "NO_FACE";
          _leftEyeOpenValue = null;
          _rightEyeOpenValue = null;
          _leftEyeProbabilityValue = null;
          _rightEyeProbabilityValue = null;
          _resetFatigueState(resetLevel: false);
          _updateFatigueLevel(shoulderWidth);
        }

        if (mounted) {
          setState(() {
            _status = "模式: $_eyeMetricMode\n"
                "肩寬: ${shoulderWidth?.toStringAsFixed(1) ?? 'N/A'} px\n"
                "左EAR/指標: ${_formatEyeValue(_leftEyeOpenValue)} 右EAR/指標: ${_formatEyeValue(_rightEyeOpenValue)}\n"
                "左MLKit: ${_formatEyeValue(_leftEyeProbabilityValue)} 右MLKit: ${_formatEyeValue(_rightEyeProbabilityValue)}\n"
                "連續閉眼: $_closedEyeFrameCount\n"
                "手勢: ${_formatGestureStatus()}\n"
                "狀態: $_fatigueLevel";
          });
        }
      }
    } catch (e) {
      debugPrint("辨識錯誤: $e");
      if (mounted) setState(() => _status = "辨識錯誤: $e");
    } finally {
      _isProcessing = false;
      if (thumbnailPath != null) {
        final file = io.File(thumbnailPath);
        if (file.existsSync()) {
          try {
            file.deleteSync();
          } catch (_) {
            debugPrint("刪除暫存縮圖失敗");
          }
        }
      }
    }
  }

  void _updateFatigueLevel(double? shoulderWidth) {
    if (_closedEyeFrameCount >= _fatigueClosedFrames) {
      _fatigueLevel = "疲勞警告：EAR 閉眼";
      return;
    }

    if (_closedEyeFrameCount >= _attentionClosedFrames) {
      _fatigueLevel = "注意：EAR 偏低";
      return;
    }

    if (shoulderWidth != null) {
      if (shoulderWidth > 780) {
        _fatigueLevel = "坐姿警告：離螢幕太近";
      } else {
        _fatigueLevel = "狀態：正常";
      }
    } else {
      _fatigueLevel = _hasFace ? "狀態：正常" : "尚未偵測到完整使用者";
    }
  }

  void _resetFatigueState({bool resetLevel = true}) {
    _closedEyeFrameCount = 0;
    if (resetLevel) _fatigueLevel = "狀態：正常";
  }

  void _updateGestureState(dynamic result) {
    _hasHand = result['hasHand'] == true;
    _detectedGesture = (result['handGesture'] as String?) ?? "none";

    if (_detectedGesture == "victory") {
      _victoryGestureFrameCount++;
    } else {
      _victoryGestureFrameCount = 0;
    }

    if (_victoryGestureFrameCount >= _victoryGestureFrames) {
      _handleGestureTriggered(_detectedGesture);
    }
  }

  Future<void> _handleGestureTriggered(String gesture) async {
    if (gesture != "victory") return;

    final now = DateTime.now();
    if (_lastGestureAlertTime != null &&
        now.difference(_lastGestureAlertTime!) < _gestureAlertCooldown) {
      return;
    }
    _lastGestureAlertTime = now;

    const message = "偵測到 YA 手勢，功能提醒已觸發。";

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(message),
          backgroundColor: Color(0xFF45B36B),
          duration: Duration(seconds: 2),
        ),
      );
    }

    try {
      await platform.invokeMethod('speak', {"message": message});
    } catch (e) {
      debugPrint("語音提醒呼叫失敗: $e");
      await _callNativeToast(message);
    }
  }

  Future<void> _showFatigueAlert() async {
    final now = DateTime.now();
    if (_lastAlertTime != null && now.difference(_lastAlertTime!) < _alertCooldown) {
      return;
    }
    _lastAlertTime = now;

    final message = "警告：EAR 偵測到連續閉眼，請休息一下！";

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: const Color(0xFFE85D75),
          duration: const Duration(seconds: 2),
        ),
      );
    }

    try {
      await platform.invokeMethod('showToast', {"message": message});
    } catch (e) {
      debugPrint("Toast 呼叫失敗: $e");
    }
  }

  Future<void> _callNativeToast(String msg) async {
    try {
      await platform.invokeMethod('showToast', {"message": msg});
    } catch (e) {
      debugPrint("手動 Toast 呼叫失敗: $e");
    }
  }

  Future<void> _restartVideo() async {
    if (!_controller.value.isInitialized) return;
    await _controller.seekTo(Duration.zero);
    await _controller.play();
  }

  Color _getStatusColor() {
    if (_detectedGesture == "victory") {
      return const Color(0xFF45B36B);
    } else if (_fatigueLevel.contains("疲勞警告")) {
      return const Color(0xFFE85D75);
    } else if (_fatigueLevel.contains("注意") || _fatigueLevel.contains("坐姿警告")) {
      return const Color(0xFFFFB648);
    } else {
      return const Color(0xFF68C7F2);
    }
  }

  String _getCompanionMessage() {
    if (!_hasFace) return "尚未偵測到使用者，請確認畫面與光線。";

    if (_detectedGesture == "victory") {
      return "已偵測到 YA 手勢，語音提醒已準備觸發。";
    } else if (_fatigueLevel.contains("疲勞警告")) {
      return "EAR 顯示你可能持續閉眼，先休息一下吧。";
    } else if (_fatigueLevel.contains("注意")) {
      return "眼睛開合指標偏低，記得留意自己的狀態。";
    } else if (_fatigueLevel.contains("坐姿警告")) {
      return "你靠得太近了，請調整坐姿保護眼睛。";
    } else {
      return "目前狀態穩定，請保持節奏。";
    }
  }

  String _formatEyeValue(double? value) {
    if (value == null || value < 0) return "--";
    return value.toStringAsFixed(3);
  }

  String _formatGestureStatus() {
    if (!_hasHand) return "未偵測到手";
    if (_detectedGesture == "victory") {
      return "YA ($_victoryGestureFrameCount/$_victoryGestureFrames)";
    }
    return "未符合 YA";
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
    if (!_fatigueLevel.contains("注意")) return const SizedBox.shrink();

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
                "EAR 指標偏低，請留意目前狀態。",
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
    if (!_fatigueLevel.contains("疲勞警告")) return const SizedBox.shrink();

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
              "EAR 偵測到使用者連續閉眼，可能出現疲勞狀態。\n建議暫時休息、喝水，或稍微離開螢幕。",
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
                  "EAR 測試資訊",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF20324D),
                  ),
                ),
                const SizedBox(height: 10),
                Text("模式：$_eyeMetricMode"),
                Text("左EAR/指標：${_formatEyeValue(_leftEyeOpenValue)}"),
                Text("右EAR/指標：${_formatEyeValue(_rightEyeOpenValue)}"),
                Text("左MLKit：${_formatEyeValue(_leftEyeProbabilityValue)}"),
                Text("右MLKit：${_formatEyeValue(_rightEyeProbabilityValue)}"),
                Text("連續閉眼次數：$_closedEyeFrameCount"),
                Text("是否偵測到人臉：${_hasFace ? "是" : "否"}"),
                Text("是否偵測到手：${_hasHand ? "是" : "否"}"),
                Text("目前手勢：${_formatGestureStatus()}"),
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
                        onPressed: () => _callNativeToast("EAR 測試提醒"),
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
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color overlayColor = _fatigueLevel.contains("疲勞警告")
        ? const Color(0x66E85D75)
        : _fatigueLevel.contains("注意")
            ? const Color(0x33FFB648)
            : const Color(0x220D3B66);

    return Scaffold(
      backgroundColor: const Color(0xFFF5FBFF),
      body: Stack(
        fit: StackFit.expand,
        children: [
          SizedBox.expand(
            child: rv.RiveAnimation.asset(
              'assets/test.riv',
              fit: BoxFit.cover,
            ),
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
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
          _buildAttentionBanner(),
          if (_fatigueLevel.contains("疲勞警告"))
            const Positioned.fill(
              child: ColoredBox(color: Color(0x22E85D75)),
            ),
          Positioned.fill(
            child: SafeArea(
              child: Column(
                children: [
                  const Spacer(),
                  if (_fatigueLevel.contains("疲勞警告")) _buildFatigueAlertCard(),
                  const Spacer(),
                ],
              ),
            ),
          ),
          _buildBottomCompanionPanel(),
          _buildDebugPanel(),
          _buildDebugToggleButton(),
        ],
      ),
    );
  }
}
