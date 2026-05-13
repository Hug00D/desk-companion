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
}
