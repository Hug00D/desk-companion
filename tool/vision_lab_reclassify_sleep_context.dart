import 'dart:convert';
import 'dart:io';

const int _baselineSampleCount = 5;
const double _maximumBaselinePitchDegrees = 25;

// Frozen from the test6 head-depth diagnostic.
const double _staticSleepingNoseDrop = 0.13;

// Developed on test7. The dynamic path requires this order:
// upright sustained eye closure -> prompt head descent -> latched sleeping.
const double _uprightNoseDropMaximum = 0.05;
const double _uprightPitchMaximumDegrees = 15;
const int _uprightClosedArmDurationMs = 300;
const int _uprightOpenDisarmDurationMs = 500;
const int _armedExpiryMs = 2000;
const double _dynamicDescentNoseDrop = 0.06;
const double _dynamicDescentPitchDegrees = 15;
const int _uprightRecoveryDurationMs = 2500;

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/vision_lab_reclassify_sleep_context.dart '
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
    'timestamp_ms',
    'face_detected',
    'pose_detected',
    'pitch',
    'image_height',
    'pose_nose_y',
    'raw_eye_closed',
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
  final baselineNoseYRatio = _baselineNoseYRatio(rows, indexes);
  final classifier = _SleepContextClassifier(
    baselineNoseYRatio: baselineNoseYRatio,
  );
  final rawStateIndex = indexes['raw_state']!;
  var sleepingFrames = 0;
  var staticSleepingFrames = 0;
  var dynamicSleepingFrames = 0;
  var dynamicTriggers = 0;

  for (final row in rows) {
    final result = classifier.classify(
      timestampMs: _requiredNumber(row, indexes, 'timestamp_ms').round(),
      hasFace: _boolean(row, indexes, 'face_detected'),
      hasPose: _boolean(row, indexes, 'pose_detected'),
      pitch: _number(row, indexes, 'pitch'),
      noseYRatio: _noseYRatio(row, indexes),
      rawEyeClosed: _boolean(row, indexes, 'raw_eye_closed'),
    );
    row[rawStateIndex] = result.sleeping ? 'sleeping' : 'normal';
    if (result.sleeping) sleepingFrames++;
    if (result.staticSleeping) staticSleepingFrames++;
    if (result.dynamicSleeping) dynamicSleepingFrames++;
    if (result.dynamicTriggered) dynamicTriggers++;
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
  stdout.writeln('raw_sleeping_frames=$sleepingFrames');
  stdout.writeln('static_sleeping_frames=$staticSleepingFrames');
  stdout.writeln('dynamic_sleeping_frames=$dynamicSleepingFrames');
  stdout.writeln('dynamic_triggers=$dynamicTriggers');
  stdout.writeln('output=${outputFile.path}');
}

double _baselineNoseYRatio(List<List<String>> rows, Map<String, int> indexes) {
  final samples = <double>[];
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
    samples.add(noseYRatio);
    if (samples.length == _baselineSampleCount) break;
  }
  if (samples.length < _baselineSampleCount) {
    throw FormatException(
      'Need $_baselineSampleCount upright face + pose samples; '
      'found ${samples.length}.',
    );
  }
  samples.sort();
  return samples[samples.length ~/ 2];
}

class _SleepContextClassifier {
  _SleepContextClassifier({required this.baselineNoseYRatio});

  final double baselineNoseYRatio;
  int? _uprightClosedStartedAtMs;
  int? _uprightOpenStartedAtMs;
  int? _armedAtMs;
  int? _uprightRecoveryStartedAtMs;
  bool _dynamicLatched = false;

  _SleepContextResult classify({
    required int timestampMs,
    required bool hasFace,
    required bool hasPose,
    required double? pitch,
    required double? noseYRatio,
    required bool rawEyeClosed,
  }) {
    final noseDrop = noseYRatio == null
        ? null
        : noseYRatio - baselineNoseYRatio;
    final upright =
        hasFace &&
        hasPose &&
        pitch != null &&
        noseDrop != null &&
        pitch.abs() <= _uprightPitchMaximumDegrees &&
        noseDrop <= _uprightNoseDropMaximum;
    final uprightClosed = upright && rawEyeClosed;
    final uprightOpen = upright && !rawEyeClosed;
    var dynamicTriggered = false;

    if (!_dynamicLatched) {
      if (uprightClosed) {
        _uprightClosedStartedAtMs ??= timestampMs;
        _uprightOpenStartedAtMs = null;
        if (timestampMs - _uprightClosedStartedAtMs! >=
            _uprightClosedArmDurationMs) {
          _armedAtMs ??= timestampMs;
        }
      } else {
        _uprightClosedStartedAtMs = null;
        if (_armedAtMs != null && uprightOpen) {
          _uprightOpenStartedAtMs ??= timestampMs;
          if (timestampMs - _uprightOpenStartedAtMs! >=
              _uprightOpenDisarmDurationMs) {
            _clearArm();
          }
        } else {
          _uprightOpenStartedAtMs = null;
        }
      }

      final armedAtMs = _armedAtMs;
      if (armedAtMs != null && timestampMs - armedAtMs > _armedExpiryMs) {
        _clearArm();
      }
      final dynamicDescent =
          _armedAtMs != null &&
          hasFace &&
          hasPose &&
          pitch != null &&
          noseDrop != null &&
          pitch.abs() >= _dynamicDescentPitchDegrees &&
          noseDrop >= _dynamicDescentNoseDrop;
      if (dynamicDescent) {
        _dynamicLatched = true;
        dynamicTriggered = true;
        _clearArm();
      }
    }

    if (_dynamicLatched) {
      // Recovery is posture-based. Requiring every recovery frame to have
      // rawEyeClosed=false lets a normal blink restart the whole timer and
      // unnecessarily extends the sleeping latch.
      if (upright) {
        _uprightRecoveryStartedAtMs ??= timestampMs;
        if (timestampMs - _uprightRecoveryStartedAtMs! >=
            _uprightRecoveryDurationMs) {
          _dynamicLatched = false;
          _uprightRecoveryStartedAtMs = null;
        }
      } else {
        _uprightRecoveryStartedAtMs = null;
      }
    }

    final staticSleeping =
        hasPose && noseDrop != null && noseDrop >= _staticSleepingNoseDrop;
    return _SleepContextResult(
      sleeping: staticSleeping || _dynamicLatched,
      staticSleeping: staticSleeping,
      dynamicSleeping: _dynamicLatched,
      dynamicTriggered: dynamicTriggered,
    );
  }

  void _clearArm() {
    _uprightClosedStartedAtMs = null;
    _uprightOpenStartedAtMs = null;
    _armedAtMs = null;
  }
}

class _SleepContextResult {
  const _SleepContextResult({
    required this.sleeping,
    required this.staticSleeping,
    required this.dynamicSleeping,
    required this.dynamicTriggered,
  });

  final bool sleeping;
  final bool staticSleeping;
  final bool dynamicSleeping;
  final bool dynamicTriggered;
}

bool _boolean(List<String> row, Map<String, int> indexes, String column) {
  return row[indexes[column]!].trim().toLowerCase() == 'true';
}

double _requiredNumber(
  List<String> row,
  Map<String, int> indexes,
  String column,
) {
  final value = _number(row, indexes, column);
  if (value == null) throw FormatException('Invalid $column value.');
  return value;
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
