import 'dart:io';

import 'package:desk_companion/vision/frame_feature_csv_classifier.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length < 2 || arguments.length > 3) {
    stderr.writeln(
      'Usage: dart run tool/vision_lab_reclassify.dart '
      '<input_frame_features.csv> <output_frame_features.csv> '
      '[--mode=p90|fixed]',
    );
    exitCode = 64;
    return;
  }

  final modeArgument = arguments.length == 3 ? arguments[2] : '--mode=p90';
  final mode = switch (modeArgument) {
    '--mode=p90' => EyeOpenEarCalibrationMode.personalizedP90,
    '--mode=fixed' => EyeOpenEarCalibrationMode.fixed,
    _ => null,
  };
  if (mode == null) {
    stderr.writeln('Unknown mode "$modeArgument"; use --mode=p90 or fixed.');
    exitCode = 64;
    return;
  }

  final summary = await FrameFeatureCsvClassifier(
    eyeCalibrationMode: mode,
  ).classifyFile(inputPath: arguments[0], outputPath: arguments[1]);
  final calibration = summary.eyeCalibration;
  stdout.writeln('mode=${mode.name}');
  stdout.writeln('frames=${summary.frameCount}');
  stdout.writeln('calibration_samples=${calibration.sampleCount}');
  stdout.writeln('calibration_fallback=${calibration.usedFallback}');
  stdout.writeln('open_ear_left=${calibration.leftOpenEar.toStringAsFixed(6)}');
  stdout.writeln(
    'open_ear_right=${calibration.rightOpenEar.toStringAsFixed(6)}',
  );
  stdout.writeln('output=${arguments[1]}');
}
