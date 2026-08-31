import 'dart:io';

import 'eye_open_ear_calibrator.dart';
import 'frame_classifier.dart';

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
  });

  final FrameClassifier frameClassifier;
  final EyeOpenEarCalibrator eyeOpenEarCalibrator;

  static const List<String> columns = <String>[
    'frame_idx',
    'timestamp_ms',
    'face_detected',
    'pose_detected',
    'ear_l',
    'ear_r',
    'yaw',
    'pitch',
    'head_offset',
    'raw_eye_closed',
    'raw_head_turned',
    'raw_posture_down',
    'raw_user_missing',
    'raw_state',
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
    if (!_sameColumns(header, columns)) {
      throw FormatException(
        'Unexpected frame_features.csv header: ${lines.first}',
      );
    }

    final rows = <_FrameFeatureCsvRow>[];
    for (var lineIndex = 1; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex];
      if (line.trim().isEmpty) continue;
      final values = line.split(',');
      if (values.length != columns.length) {
        throw FormatException(
          'Expected ${columns.length} columns at line ${lineIndex + 1}, '
          'got ${values.length}.',
        );
      }

      rows.add(
        _FrameFeatureCsvRow(
          values: values,
          timestampMs: _parseInt(values[1], lineIndex),
          features: FrameFeatures(
            faceDetected: _parseBool(values[2], lineIndex),
            poseDetected: _parseBool(values[3], lineIndex),
            earLeft: _parseOptionalDouble(values[4], lineIndex),
            earRight: _parseOptionalDouble(values[5], lineIndex),
            yaw: _parseOptionalDouble(values[6], lineIndex),
            pitch: _parseOptionalDouble(values[7], lineIndex),
            headOffset: _parseOptionalDouble(values[8], lineIndex),
          ),
        ),
      );
    }

    final eyeCalibration = eyeOpenEarCalibrator.calibrate(
      rows.map(
        (row) => EyeOpenEarSample(
          timestampMs: row.timestampMs,
          features: row.features,
        ),
      ),
    );
    final outputLines = <String>[columns.join(',')];
    for (final row in rows) {
      final values = row.values;
      final classification = frameClassifier.classify(
        row.features,
        leftOpenEyeEar: eyeCalibration.leftOpenEar,
        rightOpenEyeEar: eyeCalibration.rightOpenEar,
      );
      values[9] = classification.eyeClosed.toString();
      values[10] = classification.headTurned.toString();
      values[11] = classification.postureDown.toString();
      values[12] = classification.userMissing.toString();
      values[13] = classification.state.csvValue;
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
