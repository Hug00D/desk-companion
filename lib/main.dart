import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter/services.dart';
import 'dart:async';

void main() => runApp(const MaterialApp(home: FaceDetectionScreen()));

class FaceDetectionScreen extends StatefulWidget {
  const FaceDetectionScreen({super.key});

  @override
  _FaceDetectionScreenState createState() => _FaceDetectionScreenState();
}

class _FaceDetectionScreenState extends State<FaceDetectionScreen> {
  late VideoPlayerController _controller;
  late FaceDetector _faceDetector;
  static const platform = MethodChannel('com.example.desk_buddy/cv_channel');
  bool _isProcessing = false;
  String _status = "等待辨識...";

  @override
  void initState() {
    super.initState();
    // 1. 初始化影片播放器
    _controller = VideoPlayerController.asset('assets/test_face.mp4')
      ..initialize().then((_) {
        setState(() {});
        _controller.play();
        _controller.setLooping(true);
      });

    // 2. 初始化人臉偵測器
    _faceDetector = FaceDetector(options: FaceDetectorOptions(enableContours: true));

    // 3. 每 500 毫秒進行一次辨識測試
    Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_controller.value.isInitialized && !_isProcessing) {
        _detectFaceFromVideo();
      }
    });
  }

  Future<void> _detectFaceFromVideo() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      // 【核心邏輯】
      // 在真實開發中，我們會用 flutter_ffmpeg 或自定義截圖套件
      // 這裡我們演示當你拿到圖片後，如何丟給 ML Kit：

      // 假設你已經有一張從影片抓下來的暫存圖片路徑 imagePath
      // InputImage inputImage = InputImage.fromFilePath(imagePath);

      // 呼叫 ML Kit 偵測
      // final List<Face> faces = await _faceDetector.processImage(inputImage);

      // 這裡我們用「模擬偵測」來測試與 Kotlin 的連動：
      setState(() { _status = "AI 正在掃描畫面..."; });

      // 模擬偵測到人臉
      bool mockDetected = true;

      if (mockDetected) {
        setState(() { _status = "偵測成功：發現人臉！"; });
        // 關鍵！呼叫你寫的 Kotlin Toast
        _callNativeToast("AI 助理提示：發現使用者！");
      }

    } catch (e) {
      print("辨識出錯: $e");
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _callNativeToast(String msg) async {
    await platform.invokeMethod('showToast', {"message": msg});
  }

  @override
  void dispose() {
    _controller.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 助理 - 視覺辨識測試')),
      body: SingleChildScrollView( // 加上捲動支撐，防止鍵盤或小螢幕噴錯
        child: Column(
          children: [
            if (_controller.value.isInitialized)
            // 使用 Container 或 SizedBox 限制影片高度，防止它無限延伸
              Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.6, // 最高佔螢幕 60%
                ),
                child: AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                ),
              )
            else
              const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              ),

            const SizedBox(height: 20),

            // 顯示狀態的文字
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(_status, style: const TextStyle(fontSize: 18)),
            ),

            ElevatedButton(
              onPressed: () => _callNativeToast("手動觸發辨識結果！"),
              child: const Text('測試原生 Toast'),
            ),

            // 底部留一點空間
            const SizedBox(height: 50),
          ],
        ),
      ),
    );
  }
}