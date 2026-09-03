import 'dart:convert';
import 'dart:io';

const int _baselineSampleCount = 5;
const double _maximumBaselinePitchDegrees = 25;
const double _sleepingNoseDropThreshold = 0.13;

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/vision_lab_reclassify_head_depth.dart '
      '<input_frame_features.csv> <output_frame_features.csv>',
    );
    exitCode = 64;
    return;
  }

  final inputFile = File(arguments[0]);
  final lines = const LineSplitter()
      .convert(await inputFile.readAsString())
      .where((line) => line.trim().isNotEmpty)
      .toList(growable: false);
  if (lines.length < 2) {
    throw const FormatException('Frame feature CSV has no data rows.');
  }

  final header = lines.first.split(',');
  final indexes = <String, int>{
    for (var index = 0; index < header.length; index++) header[index]: index,
  };
  const requiredColumns = <String>[
    'face_detected',
    'pose_detected',
    'pitch',
    'image_height',
    'pose_nose_y',
    'raw_state',
  ];
  final missingColumns = requiredColumns
      .where((column) => !indexes.containsKey(column))
      .toList(growable: false);
  if (missingColumns.isNotEmpty) {
    throw FormatException(
      'Frame feature CSV is missing: ${missingColumns.join(', ')}',
    );
  }

  final rows = lines
      .skip(1)
      .map((line) => line.split(','))
      .toList(growable: false);
  final baselineSamples = <double>[];
  for (final row in rows) {
    if (!_boolean(row, indexes, 'face_detected') ||
        !_boolean(row, indexes, 'pose_detected')) {
      continue;
    }
    final pitch = _number(row, indexes, 'pitch');
    final noseYRatio = _noseYRatio(row, indexes);
    if (pitch == null ||
        pitch.abs() > _maximumBaselinePitchDegrees ||
        noseYRatio == null) {
      continue;
    }
    baselineSamples.add(noseYRatio);
    if (baselineSamples.length == _baselineSampleCount) break;
  }
  if (baselineSamples.length < _baselineSampleCount) {
    throw FormatException(
      'Need $_baselineSampleCount upright face + pose samples; '
      'found ${baselineSamples.length}.',
    );
  }

  baselineSamples.sort();
  final baselineNoseYRatio = baselineSamples[baselineSamples.length ~/ 2];
  var sleepingFrames = 0;
  final rawStateIndex = indexes['raw_state']!;
  for (final row in rows) {
    final noseYRatio = _boolean(row, indexes, 'pose_detected')
        ? _noseYRatio(row, indexes)
        : null;
    final sleeping =
        noseYRatio != null &&
        noseYRatio - baselineNoseYRatio >= _sleepingNoseDropThreshold;
    row[rawStateIndex] = sleeping ? 'sleeping' : 'normal';
    if (sleeping) sleepingFrames++;
  }

  final outputFile = File(arguments[1]);
  await outputFile.parent.create(recursive: true);
  await outputFile.writeAsString(
    <String>[header.join(','), ...rows.map((row) => row.join(','))].join('\n'),
  );

  stdout.writeln('frames=${rows.length}');
  stdout.writeln(
    'baseline_nose_y_ratio=${baselineNoseYRatio.toStringAsFixed(8)}',
  );
  stdout.writeln(
    'sleeping_nose_drop_threshold='
    '${_sleepingNoseDropThreshold.toStringAsFixed(2)}',
  );
  stdout.writeln('raw_sleeping_frames=$sleepingFrames');
  stdout.writeln('output=${outputFile.path}');
}

bool _boolean(List<String> row, Map<String, int> indexes, String column) {
  return row[indexes[column]!].trim().toLowerCase() == 'true';
}

double? _number(List<String> row, Map<String, int> indexes, String column) {
  return double.tryParse(row[indexes[column]!].trim());
}

double? _noseYRatio(List<String> row, Map<String, int> indexes) {
  final imageHeight = _number(row, indexes, 'image_height');
  final noseY = _number(row, indexes, 'pose_nose_y');
  if (imageHeight == null || imageHeight <= 0 || noseY == null) return null;
  return noseY / imageHeight;
}
