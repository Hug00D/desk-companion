import 'dart:io';

import 'package:desk_companion/vision/frame_classifier.dart';
import 'package:desk_companion/vision/frame_feature_csv_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FrameClassifier', () {
    const classifier = FrameClassifier();

    test('classifies each frame without remembering prior frames', () {
      const openFrame = FrameFeatures(
        faceDetected: true,
        poseDetected: true,
        earLeft: 0.27,
        earRight: 0.27,
        pitch: 0,
        headOffset: 0,
      );
      const blinkFrame = FrameFeatures(
        faceDetected: true,
        poseDetected: true,
        earLeft: 0.13,
        earRight: 0.13,
        pitch: 0,
        headOffset: 0,
      );

      expect(classifier.classify(openFrame).state, RawFrameState.normal);
      expect(classifier.classify(blinkFrame).state, RawFrameState.eyeClosed);
      expect(classifier.classify(openFrame).state, RawFrameState.normal);
      expect(classifier.classify(blinkFrame).state, RawFrameState.eyeClosed);
    });

    test('uses deterministic priority for simultaneous raw flags', () {
      const frame = FrameFeatures(
        faceDetected: true,
        poseDetected: true,
        earLeft: 0.13,
        earRight: 0.13,
        pitch: 40,
        headOffset: 60,
      );

      final result = classifier.classify(frame);

      expect(result.eyeClosed, isFalse, reason: 'turned head makes EAR unsafe');
      expect(result.headTurned, isTrue);
      expect(result.postureDown, isTrue);
      expect(result.userMissing, isFalse);
      expect(result.state, RawFrameState.postureDown);
    });

    test('marks a frame with no face and no pose as user missing', () {
      const frame = FrameFeatures(faceDetected: false, poseDetected: false);

      final result = classifier.classify(frame);

      expect(result.userMissing, isTrue);
      expect(result.state, RawFrameState.userMissing);
    });
  });

  test(
    'fills raw columns while preserving extracted feature columns',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'frame-classifier-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final input = File('${directory.path}/native.csv');
      final output = File('${directory.path}/frame_features.csv');
      const header = FrameFeatureCsvClassifier.columns;
      await input.writeAsString(
        '${header.join(',')}\n'
        '0,0,true,true,0.27,0.27,0,0,0,,,,,\n'
        '1,33,true,true,0.13,0.13,0,0,0,,,,,\n'
        '2,66,false,false,,,,,,,,,,\n',
      );

      await const FrameFeatureCsvClassifier().classifyFile(
        inputPath: input.path,
        outputPath: output.path,
      );

      expect(await output.readAsLines(), <String>[
        header.join(','),
        '0,0,true,true,0.27,0.27,0,0,0,false,false,false,false,normal',
        '1,33,true,true,0.13,0.13,0,0,0,true,false,false,false,eye_closed',
        '2,66,false,false,,,,,,false,false,false,true,user_missing',
      ]);
    },
  );
}
