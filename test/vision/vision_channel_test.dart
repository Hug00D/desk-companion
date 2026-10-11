import 'package:desk_companion/vision/vision_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('large asset copy sends paths instead of video bytes', () async {
    const channel = MethodChannel('vision-copy-test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'copyFlutterAssetToCache');
      expect(call.arguments, {
        'assetPath': 'assets/testVideos/dev_dual_track_01.mp4',
        'outputFileName': 'vision_lab_test.mp4',
      });
      return '/cache/vision_lab_test.mp4';
    });
    const vision = VisionChannel(channel: channel);
    expect(
      await vision.copyFlutterAssetToCache(
        assetPath: 'assets/testVideos/dev_dual_track_01.mp4',
        outputFileName: 'vision_lab_test.mp4',
      ),
      '/cache/vision_lab_test.mp4',
    );
    messenger.setMockMethodCallHandler(channel, (call) async => null);
    await expectLater(
      vision.copyFlutterAssetToCache(
        assetPath: 'assets/testVideos/dev_dual_track_01.mp4',
        outputFileName: 'vision_lab_test.mp4',
      ),
      throwsFormatException,
    );
  });

  test('extractVideoFeaturesToCsv forwards paths and parses summary', () async {
    const channel = MethodChannel('vision-channel-test');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'extractVideoFeaturesToCsv');
      expect(call.arguments, <String, Object>{
        'videoPath': '/input/test.mp4',
        'outputPath': '/output/frame_features.csv',
        'enableLiteRtPersonPresence': true,
      });
      return <String, Object>{
        'outputPath': '/output/frame_features.csv',
        'frameCount': 42,
        'droppedFrameCount': 1,
        'sourceFrameCount': 42,
        'metadataFrameCount': 43,
        'firstTimestampMs': 0,
        'lastTimestampMs': 1366,
      };
    });

    const visionChannel = VisionChannel(channel: channel);
    final result = await visionChannel.extractVideoFeaturesToCsv(
      videoPath: '/input/test.mp4',
      outputPath: '/output/frame_features.csv',
      enableLiteRtPersonPresence: true,
    );

    expect(result.outputPath, '/output/frame_features.csv');
    expect(result.frameCount, 42);
    expect(result.droppedFrameCount, 1);
    expect(result.sourceFrameCount, 42);
    expect(result.metadataFrameCount, 43);
    expect(result.firstTimestampMs, 0);
    expect(result.lastTimestampMs, 1366);
  });
}
