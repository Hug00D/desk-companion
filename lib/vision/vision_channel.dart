import 'package:flutter/services.dart';

import 'vision_result.dart';

class VisionChannel {
  const VisionChannel({
    MethodChannel channel = const MethodChannel(
      'com.example.desk_companion/cv_channel',
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

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

  Future<void> resetVision() {
    return _channel.invokeMethod<void>('resetVision');
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
