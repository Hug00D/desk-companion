import 'dart:io';

import 'package:desk_companion/vision/frame_feature_csv_classifier.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/vision_lab_reclassify.dart '
      '<input_frame_features.csv> <output_frame_features.csv>',
    );
    exitCode = 64;
    return;
  }

  final summary = await const FrameFeatureCsvClassifier().classifyFile(
    inputPath: arguments[0],
    outputPath: arguments[1],
  );
  final calibration = summary.eyeCalibration;
  stdout.writeln('frames=${summary.frameCount}');
  stdout.writeln('calibration_samples=${calibration.sampleCount}');
  stdout.writeln('calibration_fallback=${calibration.usedFallback}');
  stdout.writeln(
    'open_ear_p90_left=${calibration.leftOpenEar.toStringAsFixed(6)}',
  );
  stdout.writeln(
    'open_ear_p90_right=${calibration.rightOpenEar.toStringAsFixed(6)}',
  );
  stdout.writeln('output=${arguments[1]}');
}
