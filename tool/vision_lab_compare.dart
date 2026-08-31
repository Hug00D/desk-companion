import 'dart:io';

import 'package:desk_companion/vision/vision_lab_comparison.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 3) {
    stderr.writeln(
      'Usage: dart run tool/vision_lab_compare.dart '
      '<frame_features.csv> <ground_truth.csv> <output_directory>',
    );
    exitCode = 64;
    return;
  }

  final featurePath = arguments[0];
  final groundTruthPath = arguments[1];
  final outputDirectory = Directory(arguments[2]);
  await outputDirectory.create(recursive: true);

  final comparison = await compareVisionLabCsv(
    featurePath: featurePath,
    groundTruthPath: groundTruthPath,
  );
  final runId = _runIdFromFeaturePath(featurePath);
  final singleFramePath =
      '${outputDirectory.path}/predicted_events_single_frame_$runId.csv';
  final threeOfFivePath =
      '${outputDirectory.path}/predicted_events_3_of_5_$runId.csv';
  final metricsPath = '${outputDirectory.path}/comparison_metrics_$runId.csv';

  await writeVisionLabEvents(singleFramePath, comparison.singleFrame.events);
  await writeVisionLabEvents(threeOfFivePath, comparison.threeOfFive.events);
  await writeVisionLabMetrics(metricsPath, <VisionLabStrategyResult>[
    comparison.singleFrame,
    comparison.threeOfFive,
  ]);

  _printMetrics(comparison.singleFrame);
  _printMetrics(comparison.threeOfFive);
  stdout.writeln('single_frame_events=$singleFramePath');
  stdout.writeln('three_of_five_events=$threeOfFivePath');
  stdout.writeln('metrics=$metricsPath');
}

String _runIdFromFeaturePath(String path) {
  final fileName = path.replaceAll('\\', '/').split('/').last;
  const prefix = 'frame_features_';
  const suffix = '.csv';
  if (fileName.startsWith(prefix) && fileName.endsWith(suffix)) {
    return fileName.substring(prefix.length, fileName.length - suffix.length);
  }
  return 'run';
}

void _printMetrics(VisionLabStrategyResult result) {
  final metrics = result.metrics;
  stdout.writeln(
    '${result.strategy}: '
    'accuracy=${(metrics.frameAccuracy * 100).toStringAsFixed(1)}% '
    'false_positive_events=${metrics.falsePositiveEvents} '
    'eye_closed_false_positive_events='
    '${metrics.falsePositiveEventsByState['eye_closed'] ?? 0} '
    'missed_events=${metrics.missedEvents} '
    'switches=${metrics.stateSwitches} '
    'average_delay_ms=${metrics.averageDelayMs?.toStringAsFixed(1) ?? 'n/a'}',
  );
}
