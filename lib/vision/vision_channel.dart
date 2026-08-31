import 'package:flutter/services.dart';

import 'vision_result.dart';

class VisionVideoExtractionResult {
  const VisionVideoExtractionResult({
    required this.outputPath,
    required this.frameCount,
    required this.droppedFrameCount,
    required this.sourceFrameCount,
    required this.metadataFrameCount,
    required this.firstTimestampMs,
    required this.lastTimestampMs,
  });

  final String outputPath;
  final int frameCount;
  final int droppedFrameCount;
  final int? sourceFrameCount;
  final int? metadataFrameCount;
  final int? firstTimestampMs;
  final int? lastTimestampMs;

  factory VisionVideoExtractionResult.fromNativeMap(
    Map<dynamic, dynamic> data,
  ) {
    final outputPath = data['outputPath'];
    final frameCount = data['frameCount'];
    if (outputPath is! String || frameCount is! num) {
      throw const FormatException('Invalid video extraction result.');
    }
    return VisionVideoExtractionResult(
      outputPath: outputPath,
      frameCount: frameCount.toInt(),
      droppedFrameCount: (data['droppedFrameCount'] as num?)?.toInt() ?? 0,
      sourceFrameCount: (data['sourceFrameCount'] as num?)?.toInt(),
      metadataFrameCount: (data['metadataFrameCount'] as num?)?.toInt(),
      firstTimestampMs: (data['firstTimestampMs'] as num?)?.toInt(),
      lastTimestampMs: (data['lastTimestampMs'] as num?)?.toInt(),
    );
  }
}

class VisionChannel {
  const VisionChannel({
    MethodChannel channel = const MethodChannel(
      'com.example.desk_companion/cv_channel',
    ),
    EventChannel eventChannel = const EventChannel(
      'com.example.desk_companion/cv_stream',
    ),
  }) : _channel = channel,
       _eventChannel = eventChannel;

  final MethodChannel _channel;
  final EventChannel _eventChannel;

  Stream<VisionResult> cameraResults() {
    return _eventChannel.receiveBroadcastStream().map((dynamic result) {
      if (result is! Map) {
        throw const FormatException('Native vision result must be a map.');
      }
      return VisionResult.fromNativeMap(Map<dynamic, dynamic>.from(result));
    });
  }

  Future<VisionResult> analyzeFrame(Uint8List imageBytes) async {
    final result = await _channel.invokeMethod<dynamic>(
      'analyzeFrame',
      imageBytes,
    );

    if (result is! Map) {
      throw const FormatException('Native vision result must be a map.');
    }

    return VisionResult.fromNativeMap(Map<dynamic, dynamic>.from(result));
  }

  Future<void> showToast(String message) {
    return _channel.invokeMethod<void>('showToast', {'message': message});
  }

  Future<void> startCamera() {
    return _channel.invokeMethod<void>('startCamera');
  }

  Future<void> stopCamera() {
    return _channel.invokeMethod<void>('stopCamera');
  }

  Future<void> resetVision() {
    return _channel.invokeMethod<void>('resetVision');
  }

  Future<VisionVideoExtractionResult> extractVideoFeaturesToCsv({
    required String videoPath,
    required String outputPath,
  }) async {
    final result = await _channel.invokeMethod<dynamic>(
      'extractVideoFeaturesToCsv',
      <String, String>{'videoPath': videoPath, 'outputPath': outputPath},
    );
    if (result is! Map) {
      throw const FormatException('Native extraction result must be a map.');
    }
    return VisionVideoExtractionResult.fromNativeMap(
      Map<dynamic, dynamic>.from(result),
    );
  }

  Future<String?> copyNativeAssetToCache({
    required String assetName,
    required String outputFileName,
  }) {
    return _channel.invokeMethod<String>('copyNativeAssetToCache', {
      'assetName': assetName,
      'outputFileName': outputFileName,
    });
  }

  Future<Uint8List?> extractVideoFrame({
    required String videoPath,
    required int timeMs,
    int quality = 85,
  }) {
    return _channel.invokeMethod<Uint8List>('extractVideoFrame', {
      'videoPath': videoPath,
      'timeMs': timeMs,
      'quality': quality,
    });
  }
}
