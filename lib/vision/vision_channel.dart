import 'package:flutter/services.dart';

import 'vision_result.dart';

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
