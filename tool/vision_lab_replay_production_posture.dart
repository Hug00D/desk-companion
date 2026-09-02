import 'dart:io';

import 'package:desk_companion/vision/posture_down_detector.dart';
import 'package:desk_companion/vision/vision_result.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/vision_lab_replay_production_posture.dart '
      '<input_frame_features.csv> <output_frame_features.csv>',
    );
    exitCode = 64;
    return;
  }

  final inputFile = File(arguments[0]);
  final outputFile = File(arguments[1]);
  final lines = await inputFile.readAsLines();
  if (lines.isEmpty) throw const FormatException('Feature CSV is empty.');

  final header = lines.first.split(',');
  final indexes = <String, int>{
    for (var index = 0; index < header.length; index++) header[index]: index,
  };
  const requiredColumns = <String>[
    'frame_idx',
    'timestamp_ms',
    'face_detected',
    'pose_detected',
    'yaw',
    'pitch',
    'head_offset',
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
    'raw_eye_closed',
    'raw_head_turned',
    'raw_posture_down',
    'raw_user_missing',
    'raw_state',
  ];
  final missing = requiredColumns.where((name) => !indexes.containsKey(name));
  if (missing.isNotEmpty) {
    throw FormatException(
      'Feature CSV cannot replay production posture; missing: '
      '${missing.join(', ')}',
    );
  }

  String value(List<String> row, String name) => row[indexes[name]!];
  double? number(List<String> row, String name) {
    final raw = value(row, name);
    return raw.isEmpty ? null : double.parse(raw);
  }

  bool boolean(List<String> row, String name) =>
      value(row, name).toLowerCase() == 'true';

  final detector = PostureDownDetector();
  final output = <String>[lines.first];
  var productionDownFrames = 0;
  var coarseDownFrames = 0;

  for (var lineIndex = 1; lineIndex < lines.length; lineIndex++) {
    if (lines[lineIndex].trim().isEmpty) continue;
    final row = lines[lineIndex].split(',');
    if (row.length != header.length) {
      throw FormatException(
        'Invalid feature column count at line ${lineIndex + 1}.',
      );
    }

    if (boolean(row, 'raw_posture_down')) coarseDownFrames++;
    final frameIndex = int.parse(value(row, 'frame_idx'));
    final timestampMs = int.parse(value(row, 'timestamp_ms'));
    final result = VisionResult.fromNativeMap(<String, Object?>{
      'hasFace': boolean(row, 'face_detected'),
      'hasPose': boolean(row, 'pose_detected'),
      'imageWidth': number(row, 'image_width'),
      'imageHeight': number(row, 'image_height'),
      'poseSequence': frameIndex,
      'lsX': number(row, 'pose_left_shoulder_x'),
      'lsY': number(row, 'pose_left_shoulder_y'),
      'lsVisibility': number(row, 'pose_left_shoulder_visibility'),
      'rsX': number(row, 'pose_right_shoulder_x'),
      'rsY': number(row, 'pose_right_shoulder_y'),
      'rsVisibility': number(row, 'pose_right_shoulder_visibility'),
      'poseNoseX': number(row, 'pose_nose_x'),
      'poseNoseY': number(row, 'pose_nose_y'),
      'poseNoseVisibility': number(row, 'pose_nose_visibility'),
      'poseLeftEyeY': number(row, 'pose_left_eye_y'),
      'poseLeftEyeVisibility': number(row, 'pose_left_eye_visibility'),
      'poseRightEyeY': number(row, 'pose_right_eye_y'),
      'poseRightEyeVisibility': number(row, 'pose_right_eye_visibility'),
      'poseLeftEarY': number(row, 'pose_left_ear_y'),
      'poseLeftEarVisibility': number(row, 'pose_left_ear_visibility'),
      'poseRightEarY': number(row, 'pose_right_ear_y'),
      'poseRightEarVisibility': number(row, 'pose_right_ear_visibility'),
      'headYaw': number(row, 'yaw'),
      'headPitch': number(row, 'pitch'),
      'headOffsetScore': number(row, 'head_offset'),
    });
    final posture = detector.evaluate(
      result: result,
      shouldUpdate: true,
      observedAt: DateTime.fromMillisecondsSinceEpoch(timestampMs, isUtc: true),
    );
    final isProductionDown = posture.state == PostureDownState.down;
    if (isProductionDown) productionDownFrames++;

    row[indexes['raw_posture_down']!] = isProductionDown.toString();
    final state = switch ((
      boolean(row, 'raw_user_missing'),
      isProductionDown,
      boolean(row, 'raw_head_turned'),
      boolean(row, 'raw_eye_closed'),
    )) {
      (true, _, _, _) => 'user_missing',
      (_, true, _, _) => 'posture_down',
      (_, _, true, _) => 'head_turned',
      (_, _, _, true) => 'eye_closed',
      _ => 'normal',
    };
    row[indexes['raw_state']!] = state;
    output.add(row.join(','));
  }

  await outputFile.writeAsString('${output.join('\n')}\n');
  stdout.writeln('frames=${output.length - 1}');
  stdout.writeln('coarse_posture_down_frames=$coarseDownFrames');
  stdout.writeln('production_posture_down_frames=$productionDownFrames');
  stdout.writeln('output=${outputFile.path}');
}
