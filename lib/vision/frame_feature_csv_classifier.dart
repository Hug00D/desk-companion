import 'dart:io';

import 'eye_open_ear_calibrator.dart';
import 'frame_classifier.dart';

enum EyeOpenEarCalibrationMode { personalizedP90, fixed }

class FrameFeatureClassificationSummary {
  const FrameFeatureClassificationSummary({
    required this.frameCount,
    required this.eyeCalibration,
  });

  final int frameCount;
  final EyeOpenEarCalibration eyeCalibration;
}

class FrameFeatureCsvClassifier {
  const FrameFeatureCsvClassifier({
    this.frameClassifier = const FrameClassifier(),
    this.eyeOpenEarCalibrator = const EyeOpenEarCalibrator(),
    this.eyeCalibrationMode = EyeOpenEarCalibrationMode.personalizedP90,
  });

  final FrameClassifier frameClassifier;
  final EyeOpenEarCalibrator eyeOpenEarCalibrator;
  final EyeOpenEarCalibrationMode eyeCalibrationMode;

  static const List<String> _featureColumns = <String>[
    'frame_idx',
    'timestamp_ms',
    'face_detected',
    'pose_detected',
    'ear_l',
    'ear_r',
    'yaw',
    'pitch',
    'head_offset',
  ];

  static const List<String> _poseGeometryColumns = <String>[
    'image_width',
    'image_height',
    'pose_nose_x',
    'pose_nose_y',
    'pose_nose_visibility',
    'pose_left_eye_x',
    'pose_left_eye_y',
    'pose_left_eye_visibility',
    'pose_right_eye_x',
    'pose_right_eye_y',
    'pose_right_eye_visibility',
    'pose_left_ear_x',
    'pose_left_ear_y',
    'pose_left_ear_visibility',
    'pose_right_ear_x',
    'pose_right_ear_y',
    'pose_right_ear_visibility',
    'pose_left_shoulder_x',
    'pose_left_shoulder_y',
    'pose_left_shoulder_visibility',
    'pose_right_shoulder_x',
    'pose_right_shoulder_y',
    'pose_right_shoulder_visibility',
    'pose_left_hip_x',
    'pose_left_hip_y',
    'pose_left_hip_visibility',
    'pose_right_hip_x',
    'pose_right_hip_y',
    'pose_right_hip_visibility',
  ];

  static const List<String> _liveReplayColumns = <String>[
    'eye_open_l',
    'eye_open_r',
    'head_offset_calibrating',
  ];

  static const List<String> _classificationColumns = <String>[
    'raw_eye_closed',
    'raw_head_turned',
    'raw_posture_down',
    'raw_user_missing',
    'raw_state',
  ];

  /// Current schema emitted by native Vision Lab extraction.
  static const List<String> columns = <String>[
    ..._featureColumns,
    ..._liveReplayColumns,
    ..._poseGeometryColumns,
    ..._classificationColumns,
  ];

  /// The first Pose-context schema remains readable for test5/test6 runs
  /// extracted before fused eye openness was added.
  static const List<String> poseContextV1Columns = <String>[
    ..._featureColumns,
    ..._poseGeometryColumns,
    ..._classificationColumns,
  ];

  /// Pilot v1/v2 files remain readable so earlier runs stay reproducible.
  static const List<String> legacyColumns = <String>[
    ..._featureColumns,
    ..._classificationColumns,
  ];

  Future<FrameFeatureClassificationSummary> classifyFile({
    required String inputPath,
    required String outputPath,
  }) async {
    final input = File(inputPath);
    final lines = await input.readAsLines();
    if (lines.isEmpty) {
      throw const FormatException('frame_features.csv is empty.');
    }
    final header = lines.first.split(',');
    if (!_sameColumns(header, columns) &&
        !_sameColumns(header, poseContextV1Columns) &&
        !_sameColumns(header, legacyColumns)) {
      throw FormatException(
        'Unexpected frame_features.csv header (${header.length} columns): '
        '${lines.first}',
      );
    }
    final columnIndexes = <String, int>{
      for (var index = 0; index < header.length; index++) header[index]: index,
    };
    int columnIndex(String name) => columnIndexes[name]!;

    final rows = <_FrameFeatureCsvRow>[];
    for (var lineIndex = 1; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];
      if (line.trim().isEmpty) continue;
      final values = line.split(',');
      if (values.length != header.length) {
        throw FormatException(
          'Expected ${header.length} columns at line ${lineIndex + 1}, '
          'got ${values.length}.',
        );
      }

      rows.add(
        _FrameFeatureCsvRow(
          values: values,
          timestampMs: _parseInt(
            values[columnIndex('timestamp_ms')],
            lineIndex,
          ),
          features: FrameFeatures(
            faceDetected: _parseBool(
              values[columnIndex('face_detected')],
              lineIndex,
            ),
            poseDetected: _parseBool(
              values[columnIndex('pose_detected')],
              lineIndex,
            ),
            earLeft: _parseOptionalDouble(
              values[columnIndex('ear_l')],
              lineIndex,
            ),
            earRight: _parseOptionalDouble(
              values[columnIndex('ear_r')],
              lineIndex,
            ),
            yaw: _parseOptionalDouble(values[columnIndex('yaw')], lineIndex),
            pitch: _parseOptionalDouble(
              values[columnIndex('pitch')],
              lineIndex,
            ),
            headOffset: _parseOptionalDouble(
              values[columnIndex('head_offset')],
              lineIndex,
            ),
          ),
        ),
      );
    }

    final eyeCalibration = switch (eyeCalibrationMode) {
      EyeOpenEarCalibrationMode.personalizedP90 =>
        eyeOpenEarCalibrator.calibrate(
          rows.map(
            (row) => EyeOpenEarSample(
              timestampMs: row.timestampMs,
              features: row.features,
            ),
          ),
        ),
      EyeOpenEarCalibrationMode.fixed => EyeOpenEarCalibration(
        leftOpenEar: frameClassifier.openEyeEar,
        rightOpenEar: frameClassifier.openEyeEar,
        sampleCount: 0,
        usedFallback: false,
      ),
    };
    final outputLines = <String>[header.join(',')];
    for (final row in rows) {
      final values = row.values;
      final classification = frameClassifier.classify(
        row.features,
        leftOpenEyeEar: eyeCalibration.leftOpenEar,
        rightOpenEyeEar: eyeCalibration.rightOpenEar,
      );
      values[columnIndex('raw_eye_closed')] = classification.eyeClosed
          .toString();
      values[columnIndex('raw_head_turned')] = classification.headTurned
          .toString();
      values[columnIndex('raw_posture_down')] = classification.postureDown
          .toString();
      values[columnIndex('raw_user_missing')] = classification.userMissing
          .toString();
      values[columnIndex('raw_state')] = classification.state.csvValue;
      outputLines.add(values.join(','));
    }

    await File(
      outputPath,
    ).writeAsString('${outputLines.join('\n')}\n', flush: true);
    return FrameFeatureClassificationSummary(
      frameCount: rows.length,
      eyeCalibration: eyeCalibration,
    );
  }

  bool _sameColumns(List<String> actual, List<String> expected) {
    if (actual.length != expected.length) return false;
    for (var index = 0; index < actual.length; index++) {
      if (actual[index] != expected[index]) return false;
    }
    return true;
  }

  bool _parseBool(String value, int lineIndex) {
    return switch (value.toLowerCase()) {
      'true' => true,
      'false' => false,
      _ => throw FormatException(
        'Invalid boolean "$value" at line ${lineIndex + 1}.',
      ),
    };
  }

  int _parseInt(String value, int lineIndex) {
    final parsed = int.tryParse(value);
    if (parsed == null) {
      throw FormatException(
        'Invalid integer "$value" at line ${lineIndex + 1}.',
      );
    }
    return parsed;
  }

  double? _parseOptionalDouble(String value, int lineIndex) {
    if (value.isEmpty) return null;
    final parsed = double.tryParse(value);
    if (parsed == null) {
      throw FormatException(
        'Invalid number "$value" at line ${lineIndex + 1}.',
      );
    }
    return parsed;
  }
}

class _FrameFeatureCsvRow {
  const _FrameFeatureCsvRow({
    required this.values,
    required this.timestampMs,
    required this.features,
  });

  final List<String> values;
  final int timestampMs;
  final FrameFeatures features;
}
