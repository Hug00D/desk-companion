import 'dart:io';

import 'package:desk_companion/vision/eye_open_ear_calibrator.dart';
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

    test('accepts fixed per-eye open references without temporal memory', () {
      const asymmetricOpenFrame = FrameFeatures(
        faceDetected: true,
        poseDetected: true,
        earLeft: 0.167,
        earRight: 0.148,
        pitch: 0,
        headOffset: 0,
      );

      expect(
        classifier.classify(asymmetricOpenFrame).state,
        RawFrameState.eyeClosed,
      );
      expect(
        classifier
            .classify(
              asymmetricOpenFrame,
              leftOpenEyeEar: 0.20,
              rightOpenEyeEar: 0.17,
            )
            .state,
        RawFrameState.normal,
      );
    });
  });

  group('EyeOpenEarCalibrator', () {
    test('uses per-eye P90 and ignores blink values', () {
      final samples = <EyeOpenEarSample>[
        for (var index = 0; index < 36; index++)
          EyeOpenEarSample(
            timestampMs: index * 100,
            features: FrameFeatures(
              faceDetected: true,
              poseDetected: true,
              earLeft: index < 4 ? 0.07 : 0.19 + index / 10000,
              earRight: index < 4 ? 0.06 : 0.16 + index / 10000,
              pitch: 0,
            ),
          ),
      ];

      final calibration = const EyeOpenEarCalibrator().calibrate(samples);

      expect(calibration.usedFallback, isFalse);
      expect(calibration.sampleCount, 36);
      expect(calibration.leftOpenEar, closeTo(0.19315, 0.00001));
      expect(calibration.rightOpenEar, closeTo(0.16315, 0.00001));
    });

    test('falls back when the opening segment has too few valid frames', () {
      const samples = <EyeOpenEarSample>[
        EyeOpenEarSample(
          timestampMs: 0,
          features: FrameFeatures(
            faceDetected: true,
            poseDetected: true,
            earLeft: 0.20,
            earRight: 0.18,
          ),
        ),
      ];

      final calibration = const EyeOpenEarCalibrator().calibrate(samples);

      expect(calibration.usedFallback, isTrue);
      expect(calibration.leftOpenEar, 0.27);
      expect(calibration.rightOpenEar, 0.27);
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
        '0,0,TRUE,TRUE,0.27,0.27,0,0,0,,,,,\n'
        '1,33,true,true,0.13,0.13,0,0,0,,,,,\n'
        '2,66,false,false,,,,,,,,,,\n',
      );

      await const FrameFeatureCsvClassifier().classifyFile(
        inputPath: input.path,
        outputPath: output.path,
      );

      expect(await output.readAsLines(), <String>[
        header.join(','),
        '0,0,TRUE,TRUE,0.27,0.27,0,0,0,false,false,false,false,normal',
        '1,33,true,true,0.13,0.13,0,0,0,true,false,false,false,eye_closed',
        '2,66,false,false,,,,,,false,false,false,true,user_missing',
      ]);
    },
  );

  test('calibrates a CSV once before classifying its rows', () async {
    final directory = await Directory.systemTemp.createTemp(
      'eye-calibration-csv-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final input = File('${directory.path}/native.csv');
    final output = File('${directory.path}/frame_features.csv');
    const header = FrameFeatureCsvClassifier.columns;
    final inputLines = <String>[header.join(',')];
    for (var index = 0; index < 40; index++) {
      inputLines.add(
        '$index,${index * 100},true,true,'
        '${0.19 + index / 10000},${0.16 + index / 10000},'
        '0,0,0,,,,,',
      );
    }
    inputLines.add('40,5000,true,true,0.167,0.148,0,0,0,,,,,');
    await input.writeAsString('${inputLines.join('\n')}\n');

    final summary = await const FrameFeatureCsvClassifier().classifyFile(
      inputPath: input.path,
      outputPath: output.path,
    );
    final outputLines = await output.readAsLines();

    expect(summary.eyeCalibration.usedFallback, isFalse);
    expect(summary.eyeCalibration.sampleCount, 40);
    expect(summary.eyeCalibration.leftOpenEar, closeTo(0.19351, 0.00001));
    expect(summary.eyeCalibration.rightOpenEar, closeTo(0.16351, 0.00001));
    expect(
      outputLines.last.endsWith(',false,false,false,false,normal'),
      isTrue,
    );
  });

  test('can reclassify a CSV with the fixed 0.27 eye reference', () async {
    final directory = await Directory.systemTemp.createTemp(
      'fixed-eye-reference-csv-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final input = File('${directory.path}/native.csv');
    final output = File('${directory.path}/frame_features.csv');
    const header = FrameFeatureCsvClassifier.columns;
    await input.writeAsString(
      '${header.join(',')}\n'
      '0,0,true,true,0.167,0.148,0,0,0,,,,,\n',
    );

    final summary = await const FrameFeatureCsvClassifier(
      eyeCalibrationMode: EyeOpenEarCalibrationMode.fixed,
    ).classifyFile(inputPath: input.path, outputPath: output.path);

    expect(summary.eyeCalibration.leftOpenEar, 0.27);
    expect(summary.eyeCalibration.rightOpenEar, 0.27);
    expect((await output.readAsLines()).last.endsWith(',eye_closed'), isTrue);
  });
}
