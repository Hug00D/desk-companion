import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rive/rive.dart' as rv; // 使用 rv 避免命名空間衝突
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
  bool _hasFace = false;

  bool _showDebugPanel = false;

  static const double _eyeClosedThreshold = 0.2;
  static const int _attentionClosedFrames = 1;
  static const int _fatigueClosedFrames = 3;
  static const Duration _alertCooldown = Duration(seconds: 3);

  int _closedEyeFrameCount = 0;
  DateTime? _lastAlertTime;
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

    _detectionTimer =
        Timer.periodic(const Duration(milliseconds: 200), (timer) {
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
        await file.writeAsBytes(byteData.buffer.asUint8List(
          byteData.offsetInBytes, byteData.lengthInBytes,
        ));
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

      final dynamic result = await platform.invokeMethod('analyzeFrame', imageBytes);

      if (result != null) {
        double? shoulderWidth; // 統一用這個名字

        if (result['hasPose'] == true) {
          shoulderWidth = PoseCalculator.getWidth(
            (result['lsX'] as num).toDouble(), (result['lsY'] as num).toDouble(),
            (result['rsX'] as num).toDouble(), (result['rsY'] as num).toDouble(),
          );
        }

        if (result['hasFace'] == true) {
          _hasFace = true;
          _leftEyeOpenValue = (result['leftEye'] as num).toDouble();
          _rightEyeOpenValue = (result['rightEye'] as num).toDouble();

          if (_leftEyeOpenValue! < _eyeClosedThreshold && _rightEyeOpenValue! < _eyeClosedThreshold) {
            _closedEyeFrameCount++;
          } else {
            _closedEyeFrameCount = 0;
          }

          // 呼叫判斷函式
          _updateFatigueLevel(shoulderWidth);

          if (_closedEyeFrameCount >= _fatigueClosedFrames) {
            _showFatigueAlert(
              leftProbability: _leftEyeOpenValue!,
              rightProbability: _rightEyeOpenValue!,
            );
          }
        } else {
          _hasFace = false;
          _leftEyeOpenValue = null;
          _rightEyeOpenValue = null;
          _resetFatigueState(resetLevel: false);
          _updateFatigueLevel(shoulderWidth);
        }

        if (mounted) {
          setState(() {
            // 這裡統一變數名稱，消除紅線
            _status = "寬度: ${shoulderWidth?.toStringAsFixed(1) ?? 'N/A'} px\n"
                "左眼: ${_leftEyeOpenValue?.toStringAsFixed(2) ?? 'N/A'} 右眼: ${_rightEyeOpenValue?.toStringAsFixed(2) ?? 'N/A'}\n"
                "狀態: $_fatigueLevel";
          });
        }
      }
    } catch (e) {
      debugPrint("辨識錯誤: $e");
    } finally {
      _isProcessing = false;
      if (thumbnailPath != null) {
        final file = io.File(thumbnailPath);
        if (file.existsSync()) {
          try { file.deleteSync(); } catch (e) { debugPrint("刪檔失敗"); }
        }
      }
    }
  }

// --- 以下 Function 確保都有被呼叫到 ---

  void _updateFatigueLevel(double? shoulderWidth) {
    // --- 第一優先：先看閉眼次數，次數夠多直接變紅 ---
    if (_closedEyeFrameCount >= _fatigueClosedFrames) {
      _fatigueLevel = "疲勞警告：偵測到閉眼";
      return; // 強制結束，確保顯示紅色
    }

    // --- 第二優先：次數中等變黃 ---
    if (_closedEyeFrameCount >= _attentionClosedFrames) {
      _fatigueLevel = "注意：眨眼頻繁";
      return; // 強制結束，顯示黃色
    }

    // --- 第三優先：沒閉眼才看坐姿 ---
    if (shoulderWidth != null) {
      if (shoulderWidth > 780) { // 坐姿太近也給黃色
        _fatigueLevel = "坐姿警告：離螢幕太近";
      } else {
        _fatigueLevel = "狀態：正常"; // 藍色
      }
    } else {
      _fatigueLevel = _hasFace ? "狀態：正常" : "尚未偵測到完整使用者";
    }
  }

  void _resetFatigueState({bool resetLevel = true}) {
    _closedEyeFrameCount = 0;
    if (resetLevel) {
      _fatigueLevel = "正常";
    }
  }

  Future<void> _showFatigueAlert({
    required double leftProbability,
    required double rightProbability,
  }) async {
    final now = DateTime.now();
    if (_lastAlertTime != null && now.difference(_lastAlertTime!) < _alertCooldown) {
      return;
    }
    _lastAlertTime = now;

    final message = "警告：偵測到連續閉眼，請立刻休息！";

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
    // 1. 優先判斷疲勞（紅色）
    if (_fatigueLevel.contains("疲勞警告")) {
      return const Color(0xFFE85D75);
    }
    // 2. 判斷注意或坐姿（黃/橘色）
    else if (_fatigueLevel.contains("注意") || _fatigueLevel.contains("坐姿警告")) {
      return const Color(0xFFFFB648);
    }
    // 3. 預設（藍色/正常）
    else {
      return const Color(0xFF68C7F2);
    }
  }

  String _getCompanionMessage() {
    if (!_hasFace) {
      return "尚未偵測到使用者，請確認畫面與光線。";
    }

    // 使用 contains 檢查關鍵字，不要用 switch 寫死
    if (_fatigueLevel.contains("疲勞警告")) {
      return "偵測到持續閉眼，建議先休息一下。";
    } else if (_fatigueLevel.contains("注意")) {
      return "似乎有些疲倦了，記得留意狀態。";
    } else if (_fatigueLevel.contains("坐姿警告")) {
      return "你靠得太近了，請調整坐姿保護眼睛。";
    } else {
      return "目前狀態穩定，請保持節奏。";
    }
  }

  String _formatEyeValue(double? value) {
    if (value == null) return "--";
    return value.toStringAsFixed(2);
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
    if (_fatigueLevel != "注意") return const SizedBox.shrink();

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
            Icon(
              Icons.visibility_rounded,
              color: Color(0xFFFFA94D),
            ),
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
    if (_fatigueLevel != "疲勞警告") return const SizedBox.shrink();

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
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color overlayColor = _fatigueLevel == "疲勞警告"
        ? const Color(0x66E85D75)
        : _fatigueLevel == "注意"
        ? const Color(0x33FFB648)
        : const Color(0x220D3B66);

    return Scaffold(
      backgroundColor: const Color(0xFFF5FBFF),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Full-screen video
          // 換成你的 Rive 角色
          SizedBox.expand( // 把 const 刪掉
            child: rv.RiveAnimation.asset(
              'assets/test.riv',
              fit: BoxFit.cover,
            ),
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

          if (_fatigueLevel == "疲勞警告")
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x22E85D75),
              ),
            ),

          _buildAttentionBanner(),

          if (_fatigueLevel == "疲勞警告")
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x22E85D75),
              ),
            ),

          Positioned.fill(
            child: SafeArea(
              child: Column(
                children: [
                  const Spacer(),
                  if (_fatigueLevel == "疲勞警告") _buildFatigueAlertCard(),
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