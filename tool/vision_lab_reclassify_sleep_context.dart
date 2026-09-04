import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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

// Developed on test7 + test8. Stability is required only while collecting
// closure evidence, not after arming (when descent is the expected signal).
const double _closedPitchRangeMaximumDegrees = 3;
const double _closedNoseRangeMaximum = 0.015;

// Conservative development candidate, not a proven sleep detector. A low head
// alone is insufficient: the nose must also be near shoulder height, with
// usable Pose landmarks. This deliberately does not require visible eyes/hips.
const double _supportedShoulderGapMaximum = 0.15;
const double _minimumGeometryVisibility = 0.5;
const double _minimumShoulderWidthToImageHeight = 0.05;

Future<void> main(List<String> arguments) async {
  if (arguments.length < 2 ||
      arguments.length > 3 ||
      (arguments.length == 3 &&
          !const [
            'stable-arm',
            'legacy-arm',
            'shoulder-evidence',
          ].contains(arguments[2]))) {
    stderr.writeln(
      'Usage: dart run tool/vision_lab_reclassify_sleep_context.dart '
      '<input_frame_features.csv> <output_frame_features.csv> '
      '[stable-arm|legacy-arm|shoulder-evidence]',
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
  final mode = arguments.length == 2 ? 'stable-arm' : arguments[2];
  final requireGeometryEvidence = mode == 'shoulder-evidence';
  final requiredColumns = <String>[
    'timestamp_ms',
    'face_detected',
    'pose_detected',
    'pitch',
    'image_height',
    'pose_nose_y',
    'raw_eye_closed',
    'raw_state',
    if (requireGeometryEvidence) ...[
      'pose_nose_visibility',
      'pose_left_shoulder_x',
      'pose_left_shoulder_y',
      'pose_left_shoulder_visibility',
      'pose_right_shoulder_x',
      'pose_right_shoulder_y',
      'pose_right_shoulder_visibility',
    ],
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
  final requireStableArm = mode != 'legacy-arm';
  final classifier = SleepContextClassifier(
    baselineNoseYRatio: baselineNoseYRatio,
    requireStableArm: requireStableArm,
    requireGeometryEvidence: requireGeometryEvidence,
  );
  final rawStateIndex = indexes['raw_state']!;
  var sleepingFrames = 0;
  var staticSleepingFrames = 0;
  var dynamicSleepingFrames = 0;
  var dynamicTriggers = 0;
  var unconfirmedDepthFrames = 0;

  for (final row in rows) {
    final result = classifier.classify(
      timestampMs: _requiredNumber(row, indexes, 'timestamp_ms').round(),
      hasFace: _boolean(row, indexes, 'face_detected'),
      hasPose: _boolean(row, indexes, 'pose_detected'),
      pitch: _number(row, indexes, 'pitch'),
      noseYRatio: _noseYRatio(row, indexes),
      rawEyeClosed: _boolean(row, indexes, 'raw_eye_closed'),
      shoulderGapRatio: requireGeometryEvidence
          ? calculateShoulderGapRatio(
              imageHeight: _number(row, indexes, 'image_height'),
              noseY: _number(row, indexes, 'pose_nose_y'),
              noseVisibility: _number(row, indexes, 'pose_nose_visibility'),
              leftX: _number(row, indexes, 'pose_left_shoulder_x'),
              leftY: _number(row, indexes, 'pose_left_shoulder_y'),
              leftVisibility: _number(
                row,
                indexes,
                'pose_left_shoulder_visibility',
              ),
              rightX: _number(row, indexes, 'pose_right_shoulder_x'),
              rightY: _number(row, indexes, 'pose_right_shoulder_y'),
              rightVisibility: _number(
                row,
                indexes,
                'pose_right_shoulder_visibility',
              ),
            )
          : null,
    );
    row[rawStateIndex] = result.sleeping ? 'sleeping' : 'normal';
    if (result.sleeping) sleepingFrames++;
    if (result.staticSleeping) staticSleepingFrames++;
    if (result.dynamicSleeping) dynamicSleepingFrames++;
    if (result.dynamicTriggered) dynamicTriggers++;
    if (result.unconfirmedDepth) unconfirmedDepthFrames++;
  }

  final outputFile = File(arguments[1]);
  await outputFile.parent.create(recursive: true);
  await outputFile.writeAsString(
    <String>[header.join(','), ...rows.map((row) => row.join(','))].join('\n'),
  );

  stdout.writeln('frames=${rows.length}');
  stdout.writeln('arm_mode=$mode');
  stdout.writeln(
    'baseline_nose_y_ratio=${baselineNoseYRatio.toStringAsFixed(8)}',
  );
  stdout.writeln('raw_sleeping_frames=$sleepingFrames');
  stdout.writeln('static_sleeping_frames=$staticSleepingFrames');
  stdout.writeln('dynamic_sleeping_frames=$dynamicSleepingFrames');
  stdout.writeln('dynamic_triggers=$dynamicTriggers');
  stdout.writeln('unconfirmed_depth_frames=$unconfirmedDepthFrames');
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

// Kept in this offline tool so production App imports/behavior are unchanged.
class SleepContextClassifier {
  SleepContextClassifier({
    required this.baselineNoseYRatio,
    this.requireStableArm = true,
    this.requireGeometryEvidence = false,
  });

  final double baselineNoseYRatio;
  final bool requireStableArm;
  final bool requireGeometryEvidence;
  int? _uprightClosedStartedAtMs;
  double? _closedPitchMinimum;
  double? _closedPitchMaximum;
  double? _closedNoseMinimum;
  double? _closedNoseMaximum;
  int? _uprightOpenStartedAtMs;
  int? _armedAtMs;
  int? _uprightRecoveryStartedAtMs;
  bool _dynamicLatched = false;

  SleepContextResult classify({
    required int timestampMs,
    required bool hasFace,
    required bool hasPose,
    required double? pitch,
    required double? noseYRatio,
    required bool rawEyeClosed,
    double? shoulderGapRatio,
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
        if (requireStableArm && _armedAtMs == null) {
          _observeClosedStability(timestampMs, pitch, noseDrop);
        }
        _uprightClosedStartedAtMs ??= timestampMs;
        _uprightOpenStartedAtMs = null;
        if (timestampMs - _uprightClosedStartedAtMs! >=
            _uprightClosedArmDurationMs) {
          _armedAtMs ??= timestampMs;
        }
      } else {
        _resetClosedEvidence();
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

    final depthCandidate =
        hasPose && noseDrop != null && noseDrop >= _staticSleepingNoseDrop;
    final geometrySupported =
        shoulderGapRatio != null &&
        shoulderGapRatio.isFinite &&
        shoulderGapRatio <= _supportedShoulderGapMaximum;
    final staticSleeping =
        depthCandidate && (!requireGeometryEvidence || geometrySupported);
    return SleepContextResult(
      sleeping: staticSleeping || _dynamicLatched,
      staticSleeping: staticSleeping,
      dynamicSleeping: _dynamicLatched,
      dynamicTriggered: dynamicTriggered,
      // Binary normal means no sleep alert, not proof of wakefulness. Keep
      // unsupported depth candidates visible in diagnostic counts.
      unconfirmedDepth: depthCandidate && !staticSleeping && !_dynamicLatched,
    );
  }

  void _observeClosedStability(int timestampMs, double pitch, double noseDrop) {
    final minimumPitch = _closedPitchMinimum;
    final maximumPitch = _closedPitchMaximum;
    final minimumNose = _closedNoseMinimum;
    final maximumNose = _closedNoseMaximum;
    if (minimumPitch == null || pitch < minimumPitch) {
      _closedPitchMinimum = pitch;
    }
    if (maximumPitch == null || pitch > maximumPitch) {
      _closedPitchMaximum = pitch;
    }
    if (minimumNose == null || noseDrop < minimumNose) {
      _closedNoseMinimum = noseDrop;
    }
    if (maximumNose == null || noseDrop > maximumNose) {
      _closedNoseMaximum = noseDrop;
    }

    if (_closedPitchMaximum! - _closedPitchMinimum! >
            _closedPitchRangeMaximumDegrees ||
        _closedNoseMaximum! - _closedNoseMinimum! > _closedNoseRangeMaximum) {
      // A moving head cannot finish the earlier stable interval. Start a fresh
      // candidate here; future frames must establish a full stable 300 ms.
      _uprightClosedStartedAtMs = timestampMs;
      _closedPitchMinimum = _closedPitchMaximum = pitch;
      _closedNoseMinimum = _closedNoseMaximum = noseDrop;
    }
  }

  void _resetClosedEvidence() {
    _uprightClosedStartedAtMs = null;
    _closedPitchMinimum = _closedPitchMaximum = null;
    _closedNoseMinimum = _closedNoseMaximum = null;
  }

  void _clearArm() {
    _resetClosedEvidence();
    _uprightOpenStartedAtMs = null;
    _armedAtMs = null;
  }
}

class SleepContextResult {
  const SleepContextResult({
    required this.sleeping,
    required this.staticSleeping,
    required this.dynamicSleeping,
    required this.dynamicTriggered,
    this.unconfirmedDepth = false,
  });

  final bool sleeping;
  final bool staticSleeping;
  final bool dynamicSleeping;
  final bool dynamicTriggered;
  final bool unconfirmedDepth;
}

/// Signed vertical nose-to-shoulder gap, in projected shoulder-width units.
/// Null means unavailable/unreliable, never evidence that eyes are closed.
double? calculateShoulderGapRatio({
  required double? imageHeight,
  required double? noseY,
  required double? noseVisibility,
  required double? leftX,
  required double? leftY,
  required double? leftVisibility,
  required double? rightX,
  required double? rightY,
  required double? rightVisibility,
}) {
  if (imageHeight == null ||
      !imageHeight.isFinite ||
      imageHeight <= 0 ||
      noseY == null ||
      !noseY.isFinite ||
      leftX == null ||
      !leftX.isFinite ||
      leftY == null ||
      !leftY.isFinite ||
      rightX == null ||
      !rightX.isFinite ||
      rightY == null ||
      !rightY.isFinite) {
    return null;
  }
  for (final visibility in [noseVisibility, leftVisibility, rightVisibility]) {
    if (visibility == null ||
        !visibility.isFinite ||
        visibility < _minimumGeometryVisibility ||
        visibility > 1) {
      return null;
    }
  }
  final dx = leftX - rightX;
  final dy = leftY - rightY;
  final width = math.sqrt(dx * dx + dy * dy);
  if (!width.isFinite ||
      width < imageHeight * _minimumShoulderWidthToImageHeight) {
    return null;
  }
  return ((leftY + rightY) / 2 - noseY) / width;
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
