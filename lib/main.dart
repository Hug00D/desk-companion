import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

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

  String? _tempVideoPath;

  Future<void> _detectFaceFromVideo() async {
    if (_isProcessing || !_controller.value.isInitialized) return;
    _isProcessing = true;

    try {
      if (_tempVideoPath == null) {
        final byteData = await rootBundle.load('assets/test_face.mp4');
        final directory = await getTemporaryDirectory();
        final file = File('${directory.path}/temp_video.mp4');
        await file.writeAsBytes(byteData.buffer.asUint8List(
            byteData.offsetInBytes, byteData.lengthInBytes));
        _tempVideoPath = file.path;
        print("影片已成功搬移至: $_tempVideoPath");
      }

      final String? thumbnailPath = await VideoThumbnail.thumbnailFile(
        video: _tempVideoPath!,
        thumbnailPath: (await getTemporaryDirectory()).path,
        imageFormat: ImageFormat.JPEG,
        timeMs: _controller.value.position.inMilliseconds,
        quality: 50
      );

      if(thumbnailPath != null) {
        File imageFile = File(thumbnailPath);
        Uint8List imageBytes = await imageFile.readAsBytes();

        final dynamic result = await platform.invokeMethod(
            'analyzeFrame', imageBytes);

        if (result != null && result['hasFace'] == true) {
          double leftProbability = result['leftEye'];
          double rightProbability = result['rightEye'];

          setState(() {
            _status =
            "Kotlin 辨識成功！\n左眼開度: ${leftProbability.toStringAsFixed(
                2)}\n右眼開度: ${rightProbability.toStringAsFixed(2)}";
          });

          // 如果眼睛閉起來 (小於 0.2)，叫 Kotlin 跳警告
          if (leftProbability < 0.2 && rightProbability < 0.2) {
            platform.invokeMethod(
                'showToast', {"message": "警告：偵測到疲勞閉眼！"});
          }
        } else {
          setState(() {
            _status = "Kotlin 沒看到人臉...";
          });
        }
      }
    } catch (e) {
      debugPrint("辨識出錯: $e");
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