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

    test('can apply continuous pitch compensation before 25 degrees', () {
      const frame = FrameFeatures(
        faceDetected: true,
        poseDetected: true,
        earLeft: 0.15,
        earRight: 0.15,
        pitch: 20,
        headOffset: 0,
      );

      expect(classifier.classify(frame).state, RawFrameState.eyeClosed);
      expect(
        const FrameClassifier(
          continuousReadingPitchCompensation: true,
        ).classify(frame).state,
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

  test('fills raw columns while preserving extracted feature columns', () async {
    final directory = await Directory.systemTemp.createTemp(
      'frame-classifier-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final input = File('${directory.path}/native.csv');
    final output = File('${directory.path}/frame_features.csv');
    const header = FrameFeatureCsvClassifier.columns;
    await input.writeAsString(
      '${header.join(',')}\n'
      '${_csvRow(header, <String, Object?>{'frame_idx': 0, 'timestamp_ms': 0, 'face_detected': 'TRUE', 'pose_detected': 'TRUE', 'ear_l': 0.27, 'ear_r': 0.27, 'yaw': 0, 'pitch': 0, 'head_offset': 0, 'eye_open_l': 0.91, 'eye_open_r': 0.89, 'head_offset_calibrating': false, 'image_width': 640, 'image_height': 480, 'pose_nose_x': 320.5, 'pose_nose_y': 120.25, 'pose_nose_visibility': 0.98, 'pose_left_shoulder_x': 240.0, 'pose_left_shoulder_y': 260.0, 'pose_left_shoulder_visibility': 0.95, 'pose_right_shoulder_x': 400.0, 'pose_right_shoulder_y': 260.0, 'pose_right_shoulder_visibility': 0.96, 'pose_left_hip_x': 270.0, 'pose_left_hip_y': 430.0, 'pose_left_hip_visibility': 0.90, 'pose_right_hip_x': 370.0, 'pose_right_hip_y': 430.0, 'pose_right_hip_visibility': 0.91})}\n'
      '${_csvRow(header, <String, Object?>{'frame_idx': 1, 'timestamp_ms': 33, 'face_detected': true, 'pose_detected': true, 'ear_l': 0.13, 'ear_r': 0.13, 'yaw': 0, 'pitch': 0, 'head_offset': 0})}\n'
      '${_csvRow(header, <String, Object?>{'frame_idx': 2, 'timestamp_ms': 66, 'face_detected': false, 'pose_detected': false})}\n',
    );

    await const FrameFeatureCsvClassifier().classifyFile(
      inputPath: input.path,
      outputPath: output.path,
    );

    expect(await output.readAsLines(), <String>[
      header.join(','),
      _csvRow(header, <String, Object?>{
        'frame_idx': 0,
        'timestamp_ms': 0,
        'face_detected': 'TRUE',
        'pose_detected': 'TRUE',
        'ear_l': 0.27,
        'ear_r': 0.27,
        'yaw': 0,
        'pitch': 0,
        'head_offset': 0,
        'eye_open_l': 0.91,
        'eye_open_r': 0.89,
        'head_offset_calibrating': false,
        'image_width': 640,
        'image_height': 480,
        'pose_nose_x': 320.5,
        'pose_nose_y': 120.25,
        'pose_nose_visibility': 0.98,
        'pose_left_shoulder_x': 240.0,
        'pose_left_shoulder_y': 260.0,
        'pose_left_shoulder_visibility': 0.95,
        'pose_right_shoulder_x': 400.0,
        'pose_right_shoulder_y': 260.0,
        'pose_right_shoulder_visibility': 0.96,
        'pose_left_hip_x': 270.0,
        'pose_left_hip_y': 430.0,
        'pose_left_hip_visibility': 0.90,
        'pose_right_hip_x': 370.0,
        'pose_right_hip_y': 430.0,
        'pose_right_hip_visibility': 0.91,
        'raw_eye_closed': false,
        'raw_head_turned': false,
        'raw_posture_down': false,
        'raw_user_missing': false,
        'raw_state': 'normal',
      }),
      _csvRow(header, <String, Object?>{
        'frame_idx': 1,
        'timestamp_ms': 33,
        'face_detected': true,
        'pose_detected': true,
        'ear_l': 0.13,
        'ear_r': 0.13,
        'yaw': 0,
        'pitch': 0,
        'head_offset': 0,
        'raw_eye_closed': true,
        'raw_head_turned': false,
        'raw_posture_down': false,
        'raw_user_missing': false,
        'raw_state': 'eye_closed',
      }),
      _csvRow(header, <String, Object?>{
        'frame_idx': 2,
        'timestamp_ms': 66,
        'face_detected': false,
        'pose_detected': false,
        'raw_eye_closed': false,
        'raw_head_turned': false,
        'raw_posture_down': false,
        'raw_user_missing': true,
        'raw_state': 'user_missing',
      }),
    ]);
  });

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
        _csvRow(header, <String, Object?>{
          'frame_idx': index,
          'timestamp_ms': index * 100,
          'face_detected': true,
          'pose_detected': true,
          'ear_l': 0.19 + index / 10000,
          'ear_r': 0.16 + index / 10000,
          'yaw': 0,
          'pitch': 0,
          'head_offset': 0,
        }),
      );
    }
    inputLines.add(
      _csvRow(header, <String, Object?>{
        'frame_idx': 40,
        'timestamp_ms': 5000,
        'face_detected': true,
        'pose_detected': true,
        'ear_l': 0.167,
        'ear_r': 0.148,
        'yaw': 0,
        'pitch': 0,
        'head_offset': 0,
      }),
    );
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
      '${_csvRow(header, <String, Object?>{'frame_idx': 0, 'timestamp_ms': 0, 'face_detected': true, 'pose_detected': true, 'ear_l': 0.167, 'ear_r': 0.148, 'yaw': 0, 'pitch': 0, 'head_offset': 0})}\n',
    );

    final summary = await const FrameFeatureCsvClassifier(
      eyeCalibrationMode: EyeOpenEarCalibrationMode.fixed,
    ).classifyFile(inputPath: input.path, outputPath: output.path);

    expect(summary.eyeCalibration.leftOpenEar, 0.27);
    expect(summary.eyeCalibration.rightOpenEar, 0.27);
    expect((await output.readAsLines()).last.endsWith(',eye_closed'), isTrue);
  });

  test('keeps legacy 14-column Vision Lab files reclassifiable', () async {
    final directory = await Directory.systemTemp.createTemp(
      'legacy-frame-features-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final input = File('${directory.path}/legacy.csv');
    final output = File('${directory.path}/legacy-output.csv');
    const header = FrameFeatureCsvClassifier.legacyColumns;
    await input.writeAsString(
      '${header.join(',')}\n'
      '${_csvRow(header, <String, Object?>{'frame_idx': 0, 'timestamp_ms': 0, 'face_detected': true, 'pose_detected': true, 'ear_l': 0.27, 'ear_r': 0.27, 'yaw': 0, 'pitch': 0, 'head_offset': 0})}\n',
    );

    await const FrameFeatureCsvClassifier().classifyFile(
      inputPath: input.path,
      outputPath: output.path,
    );

    final outputLines = await output.readAsLines();
    expect(outputLines.first, header.join(','));
    expect(outputLines.last.endsWith(',normal'), isTrue);
    expect(outputLines.last.split(','), hasLength(14));
  });

  test('keeps the 43-column Pose-context schema reclassifiable', () async {
    final directory = await Directory.systemTemp.createTemp(
      'pose-context-v1-frame-features-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final input = File('${directory.path}/pose-v1.csv');
    final output = File('${directory.path}/pose-v1-output.csv');
    const header = FrameFeatureCsvClassifier.poseContextV1Columns;
    await input.writeAsString(
      '${header.join(',')}\n'
      '${_csvRow(header, <String, Object?>{'frame_idx': 0, 'timestamp_ms': 0, 'face_detected': true, 'pose_detected': true, 'ear_l': 0.27, 'ear_r': 0.27, 'yaw': 0, 'pitch': 0, 'head_offset': 0, 'image_width': 640, 'image_height': 480})}\n',
    );

    await const FrameFeatureCsvClassifier().classifyFile(
      inputPath: input.path,
      outputPath: output.path,
    );

    final outputLines = await output.readAsLines();
    expect(outputLines.first, header.join(','));
    expect(outputLines.last.endsWith(',normal'), isTrue);
    expect(outputLines.last.split(','), hasLength(43));
  });
}

String _csvRow(List<String> header, Map<String, Object?> values) {
  return header.map((column) => values[column]?.toString() ?? '').join(',');
}
