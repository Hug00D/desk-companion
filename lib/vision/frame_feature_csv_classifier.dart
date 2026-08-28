import 'dart:io';

import 'frame_classifier.dart';

class FrameFeatureCsvClassifier {
  const FrameFeatureCsvClassifier({
    this.frameClassifier = const FrameClassifier(),
  });

  final FrameClassifier frameClassifier;

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

  Future<void> classifyFile({
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

    final outputLines = <String>[columns.join(',')];
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

      final classification = frameClassifier.classify(
        FrameFeatures(
          faceDetected: _parseBool(values[2], lineIndex),
          poseDetected: _parseBool(values[3], lineIndex),
          earLeft: _parseOptionalDouble(values[4], lineIndex),
          earRight: _parseOptionalDouble(values[5], lineIndex),
          yaw: _parseOptionalDouble(values[6], lineIndex),
          pitch: _parseOptionalDouble(values[7], lineIndex),
          headOffset: _parseOptionalDouble(values[8], lineIndex),
        ),
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
  }

  bool _sameColumns(List<String> actual, List<String> expected) {
    if (actual.length != expected.length) return false;
    for (var index = 0; index < actual.length; index++) {
      if (actual[index] != expected[index]) return false;
    }
    return true;
  }

  bool _parseBool(String value, int lineIndex) {
    return switch (value) {
      'true' => true,
      'false' => false,
      _ => throw FormatException(
        'Invalid boolean "$value" at line ${lineIndex + 1}.',
      ),
    };
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
