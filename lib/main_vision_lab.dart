import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'vision/frame_feature_csv_classifier.dart';
import 'vision/vision_channel.dart';

void main() => runApp(const VisionLabApp());

class VisionLabApp extends StatelessWidget {
  const VisionLabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vision Lab Pilot v1',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const VisionLabScreen(),
    );
  }
}

class VisionLabScreen extends StatefulWidget {
  const VisionLabScreen({super.key});

  @override
  State<VisionLabScreen> createState() => _VisionLabScreenState();
}

class _VisionLabScreenState extends State<VisionLabScreen> {
  static const String _assetPath = 'assets/test.mp4';
  static const String _cachedVideoName = 'vision_lab_test.mp4';

  final VisionChannel _visionChannel = const VisionChannel();
  final FrameFeatureCsvClassifier _csvClassifier =
      const FrameFeatureCsvClassifier();
  final List<VisionVideoExtractionResult> _completedRuns = [];
  VideoPlayerController? _videoController;
  String? _videoPath;
  String _status = '正在準備測試影片…';
  bool _isExtracting = false;

  @override
  void initState() {
    super.initState();
    unawaited(_prepareVideo());
  }

  Future<void> _prepareVideo() async {
    try {
      final temporaryDirectory = await getTemporaryDirectory();
      final videoFile = File('${temporaryDirectory.path}/$_cachedVideoName');
      final data = await rootBundle.load(_assetPath);
      await videoFile.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );

      final controller = VideoPlayerController.file(videoFile);
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);

      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _videoPath = videoFile.path;
        _videoController = controller;
        _status = '影片已就緒。按下按鈕後由原生端逐幀解碼；預覽不驅動推論。';
      });
      await controller.play();
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '影片準備失敗：$error');
    }
  }

  /// Derives a filename-safe identifier from [_assetPath], e.g. `test`.
  String _videoSlug() {
    final fileName = _assetPath.split('/').last;
    final withoutExtension = fileName.contains('.')
        ? fileName.substring(0, fileName.lastIndexOf('.'))
        : fileName;
    final slug = withoutExtension.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    return slug.isEmpty ? 'video' : slug;
  }

  Future<void> _extractFeatures() async {
    final videoPath = _videoPath;
    if (_isExtracting || videoPath == null) return;

    setState(() {
      _isExtracting = true;
      _status = '原生端正在逐幀解碼與執行 MediaPipe…';
    });
    await _videoController?.pause();

    try {
      // 外部專屬目錄可用 adb pull 直接抓出 CSV；內部 documents 目錄抓不到。
      final outputDirectory =
          await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      // The video slug keeps each run identifiable once several videos share
      // the output directory; every downstream file inherits it through the
      // run id, so predictions and ground truth cannot be paired by mistake.
      final runId = '${_videoSlug()}_${DateTime.now().microsecondsSinceEpoch}';
      final outputPath = '${outputDirectory.path}/frame_features_$runId.csv';
      final nativeOutputPath = '$outputPath.native';
      final extraction = await _visionChannel.extractVideoFeaturesToCsv(
        videoPath: videoPath,
        outputPath: nativeOutputPath,
      );
      await _csvClassifier.classifyFile(
        inputPath: nativeOutputPath,
        outputPath: outputPath,
      );
      await File(nativeOutputPath).delete();
      final classifiedExtraction = VisionVideoExtractionResult(
        outputPath: outputPath,
        frameCount: extraction.frameCount,
        droppedFrameCount: extraction.droppedFrameCount,
        sourceFrameCount: extraction.sourceFrameCount,
        metadataFrameCount: extraction.metadataFrameCount,
        firstTimestampMs: extraction.firstTimestampMs,
        lastTimestampMs: extraction.lastTimestampMs,
      );
      if (!mounted) return;
      setState(() {
        _completedRuns.add(classifiedExtraction);
        _status =
            '完成 ${extraction.frameCount} 幀；raw_state 是零記憶單幀輸出，'
            '請播放影片確認眨眼幀會短暫跳動。';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = '抽取失敗：$error');
    } finally {
      await _videoController?.play();
      if (mounted) setState(() => _isExtracting = false);
    }
  }

  @override
  void dispose() {
    unawaited(_videoController?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _videoController;
    return Scaffold(
      appBar: AppBar(title: const Text('Vision Lab Pilot v1')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (controller != null && controller.value.isInitialized)
              AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: VideoPlayer(controller),
              )
            else
              const AspectRatio(
                aspectRatio: 16 / 9,
                child: Center(child: CircularProgressIndicator()),
              ),
            const SizedBox(height: 20),
            Text(_status),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _isExtracting || _videoPath == null
                  ? null
                  : _extractFeatures,
              icon: _isExtracting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: const Text('產生 frame_features.csv'),
            ),
            if (_completedRuns.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text('本次啟動完成的輸出：'),
              const SizedBox(height: 8),
              for (final run in _completedRuns)
                SelectableText(
                  '${run.frameCount}/${run.sourceFrameCount ?? '?'} frames | '
                  'dropped=${run.droppedFrameCount} | '
                  'metadata=${run.metadataFrameCount ?? '?'} | '
                  '${run.firstTimestampMs}–${run.lastTimestampMs} ms\n'
                  '${run.outputPath}',
                ),
            ],
          ],
        ),
      ),
    );
  }
}
