import 'dart:io';

import 'companion_state_evaluator.dart';
import 'vision_result.dart';

class VisionLabReplayFrame {
  const VisionLabReplayFrame({
    required this.frameIndex,
    required this.timestampMs,
    required this.result,
    this.rawEyeClosed,
  });

  final int frameIndex;
  final int timestampMs;
  final VisionResult result;
  final bool? rawEyeClosed;
}

const visionLabReplayColumns = <String>[
  'frame_idx',
  'timestamp_ms',
  'face_detected',
  'pose_detected',
  'yaw',
  'pitch',
  'head_offset',
  'eye_open_l',
  'eye_open_r',
  'head_offset_calibrating',
  'image_width',
  'image_height',
  'pose_nose_x',
  'pose_nose_y',
  'pose_nose_visibility',
  'pose_left_eye_y',
  'pose_left_eye_visibility',
  'pose_right_eye_y',
  'pose_right_eye_visibility',
  'pose_left_ear_y',
  'pose_left_ear_visibility',
  'pose_right_ear_y',
  'pose_right_ear_visibility',
  'pose_left_shoulder_x',
  'pose_left_shoulder_y',
  'pose_left_shoulder_visibility',
  'pose_right_shoulder_x',
  'pose_right_shoulder_y',
  'pose_right_shoulder_visibility',
];

// Vision Lab emits unquoted numeric/boolean cells. Reject quoted input rather
// than silently interpreting it as this restricted format.
Future<List<List<String>>> readVisionLabReplayCsv(String path) async {
  final lines = await File(path).readAsLines();
  if (lines.any((line) => line.contains('"'))) {
    throw const FormatException('Vision Lab CSV must contain unquoted cells.');
  }
  return lines
      .where((line) => line.trim().isNotEmpty)
      .map((line) => line.split(','))
      .toList(growable: false);
}

List<VisionLabReplayFrame> parseVisionLabReplayFrames(
  List<List<String>> rows, {
  bool requireRawEyeClosed = false,
}) {
  if (rows.length < 2) {
    throw const FormatException('Feature CSV has no frame rows.');
  }
  final header = rows.first;
  if (header.toSet().length != header.length) {
    throw const FormatException('Feature CSV has duplicate columns.');
  }
  final indexes = <String, int>{
    for (var index = 0; index < header.length; index++) header[index]: index,
  };
  final missing = <String>[
    ...visionLabReplayColumns,
    if (requireRawEyeClosed) 'raw_eye_closed',
  ].where((name) => !indexes.containsKey(name));
  if (missing.isNotEmpty) {
    throw FormatException(
      'Feature CSV cannot replay CompanionStateEvaluator; '
      'missing: ${missing.join(', ')}',
    );
  }
  final frames = <VisionLabReplayFrame>[];
  for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
    final row = rows[rowIndex];
    if (row.length != header.length) {
      throw FormatException('Invalid feature row ${rowIndex + 1}.');
    }
    String value(String name) => row[indexes[name]!];
    double? number(String name) {
      final raw = value(name);
      if (raw.isEmpty) return null;
      final parsed = double.tryParse(raw);
      if (parsed == null || !parsed.isFinite) {
        throw FormatException('Invalid $name at row ${rowIndex + 1}.');
      }
      return parsed;
    }

    bool boolean(String name) => switch (value(name).toLowerCase()) {
      'true' => true,
      'false' => false,
      _ => throw FormatException('Invalid $name at row ${rowIndex + 1}.'),
    };
    final frameIndex = int.parse(value('frame_idx'));
    final timestampMs = int.parse(value('timestamp_ms'));
    final hasFace = boolean('face_detected');
    // Native extraction omits this face-only field when no face is found.
    final calibrating = value('head_offset_calibrating').isEmpty && !hasFace
        ? false
        : boolean('head_offset_calibrating');
    if (frameIndex < 0 ||
        timestampMs < 0 ||
        (frames.isNotEmpty &&
            (timestampMs <= frames.last.timestampMs ||
                frameIndex <= frames.last.frameIndex))) {
      throw FormatException(
        'Frame index and timestamp_ms must increase '
        'at row ${rowIndex + 1}.',
      );
    }
    frames.add(
      VisionLabReplayFrame(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        rawEyeClosed: requireRawEyeClosed ? boolean('raw_eye_closed') : null,
        result: VisionResult.fromNativeMap(<String, Object?>{
          'hasFace': hasFace,
          'hasPose': boolean('pose_detected'),
          'imageWidth': number('image_width'),
          'imageHeight': number('image_height'),
          'poseSequence': frameIndex,
          'lsX': number('pose_left_shoulder_x'),
          'lsY': number('pose_left_shoulder_y'),
          'lsVisibility': number('pose_left_shoulder_visibility'),
          'rsX': number('pose_right_shoulder_x'),
          'rsY': number('pose_right_shoulder_y'),
          'rsVisibility': number('pose_right_shoulder_visibility'),
          'poseNoseX': number('pose_nose_x'),
          'poseNoseY': number('pose_nose_y'),
          'poseNoseVisibility': number('pose_nose_visibility'),
          'poseLeftEyeY': number('pose_left_eye_y'),
          'poseLeftEyeVisibility': number('pose_left_eye_visibility'),
          'poseRightEyeY': number('pose_right_eye_y'),
          'poseRightEyeVisibility': number('pose_right_eye_visibility'),
          'poseLeftEarY': number('pose_left_ear_y'),
          'poseLeftEarVisibility': number('pose_left_ear_visibility'),
          'poseRightEarY': number('pose_right_ear_y'),
          'poseRightEarVisibility': number('pose_right_ear_visibility'),
          'leftEye': number('eye_open_l'),
          'rightEye': number('eye_open_r'),
          'headYaw': number('yaw'),
          'headPitch': number('pitch'),
          'headOffsetScore': number('head_offset'),
          'headOffsetCalibrating': calibrating,
        }),
      ),
    );
  }
  return frames;
}

class VisionLabCompanionReplay {
  final CompanionStateEvaluator _evaluator = CompanionStateEvaluator();
  int _closedFrames = 0;
  int _distractedFrames = 0;

  CompanionAnalysis evaluate(VisionLabReplayFrame frame) {
    final analysis = _evaluator.evaluate(
      result: frame.result,
      previousClosedFrameCount: _closedFrames,
      previousDistractedFrameCount: _distractedFrames,
      isFreshPoseResult: true,
      observedAt: DateTime.fromMillisecondsSinceEpoch(
        frame.timestampMs,
        isUtc: true,
      ),
    );
    _closedFrames = analysis.eyeResult.closedFrameCount;
    _distractedFrames = analysis.headOffsetResult.distractedFrameCount;
    return analysis;
  }

  void reset() {
    _evaluator.reset();
    _closedFrames = 0;
    _distractedFrames = 0;
  }
}

const visionLabReplayHeader =
    'frame_idx,timestamp_ms,status,cause,is_sleeping,'
    'eye_state,pose_state,posture_score';

String visionLabReplayRow(
  VisionLabReplayFrame frame,
  CompanionAnalysis analysis,
) =>
    '${frame.frameIndex},${frame.timestampMs},${analysis.status.name},'
    '${analysis.cause.name},${analysis.status == CompanionStatus.sleeping},'
    '${analysis.eyeResult.state.name},${analysis.poseResult.state.name},'
    '${analysis.postureDownResult.score?.toString() ?? ''}';
