import 'dart:io';

import 'package:desk_companion/vision/dual_track_context_classifier.dart';
import 'package:desk_companion/vision/dual_track_lab_report.dart';
import 'package:desk_companion/vision/posture_down_detector.dart';
import 'package:desk_companion/vision/vision_lab_comparison.dart';
import 'package:desk_companion/vision/vision_lab_replay.dart';

const _usage =
    'Usage: dart run tool/vision_lab_dual_track.dart '
    '<frame_features.csv> <sleeping_ground_truth.csv> <output_directory> '
    '--window-ms=2000|--window-ms=3000 [--presence-context [--head-score-sum]]';

Future<void> main(List<String> arguments) async {
  final flags = arguments.skip(4).toSet();
  if (arguments.length < 4 ||
      arguments.length > 6 ||
      flags.length != arguments.length - 4 ||
      flags.any(
        (flag) =>
            !const {'--presence-context', '--head-score-sum'}.contains(flag),
      ) ||
      (flags.contains('--head-score-sum') &&
          !flags.contains('--presence-context')) ||
      !const {'--window-ms=2000', '--window-ms=3000'}.contains(arguments[3])) {
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }
  try {
    final paths = await runDualTrackLab(
      featurePath: arguments[0],
      truthPath: arguments[1],
      outputDirectory: arguments[2],
      windowMs: int.parse(arguments[3].split('=').last),
      enablePresenceContext: flags.contains('--presence-context'),
      enableHeadScoreSum: flags.contains('--head-score-sum'),
    );
    for (final path in paths) {
      stdout.writeln('output=$path');
    }
  } on FormatException catch (error) {
    stderr.writeln(error);
    stderr.writeln(_usage);
    exitCode = 65;
  } on FileSystemException catch (error) {
    stderr.writeln(error);
    stderr.writeln(_usage);
    exitCode = 74;
  } on StateError catch (error) {
    stderr.writeln(error);
    stderr.writeln(_usage);
    exitCode = 65;
  }
}

Future<List<String>> runDualTrackLab({
  required String featurePath,
  required String truthPath,
  required String outputDirectory,
  required int windowMs,
  bool enablePresenceContext = false,
  bool enableHeadScoreSum = false,
}) async {
  final classifier = DualTrackContextClassifier(
    windowMs: windowMs,
    enablePresenceContext: enablePresenceContext,
    enableHeadScoreSum: enableHeadScoreSum,
  );
  final frames = parseVisionLabReplayFrames(
    await readVisionLabReplayCsv(featurePath),
    requireRawEyeClosed: true,
  );
  final truth = await readGroundTruthEvents(truthPath);
  final replay = VisionLabCompanionReplay();
  final outputLines = <String>[
    'frame_idx,timestamp_ms,fast_status,fast_cause,low_head_candidate,'
        'slow_state,slow_window_ms,evidence_eye,evidence_motion,evidence_posture,'
        'data_quality,final_state,configured_window_ms,eye_coverage,pose_coverage,'
        'closed_duration_ms,nose_drop,pitch_range,nose_range,'
        'motion_evidence_at_ms,eye_descent_at_ms,drowsy_confirmed'
        '${enablePresenceContext ? ',presence_context,presence_reason,face_missing_ms,loss_history_reliable,side_exit_evidence,relative_descent_evidence,sleep_supported' : ''}'
        '${enableHeadScoreSum ? ',head_score_state,head_score_used,head_score_imputed,head_score_sum,head_score_samples,head_score_measured_high_samples' : ''}',
  ];
  final comparisonFrames = <VisionLabFrame>[];
  final states = <String>[];
  for (final frame in frames) {
    final fast = replay.evaluate(frame);
    final dual = classifier.classify(
      timestampMs: frame.timestampMs,
      result: frame.result,
      fastState: fast.state,
      rawEyeClosed: frame.rawEyeClosed!,
      strongPostureEvidence:
          fast.postureDownResult.state == PostureDownState.down &&
          !fast.postureDownResult.isCalibrating &&
          DualTrackContextClassifier.hasReliablePoseGeometry(frame.result),
    );
    outputLines.add(
      '${frame.frameIndex},${frame.timestampMs},${fast.status.name},${fast.cause.name},'
      '${dual.lowHeadCandidate},${dual.slowState.csvValue},${dual.slowWindowMs},'
      '${dual.evidenceEye},${dual.evidenceMotion},${dual.evidencePosture},'
      '${dual.dataQuality},${dual.finalState},$windowMs,'
      '${dual.eyeCoverage.toStringAsFixed(6)},${dual.poseCoverage.toStringAsFixed(6)},'
      '${dual.closedDurationMs},${dual.noseDrop ?? ''},'
      '${dual.pitchRange ?? ''},${dual.noseRange ?? ''},'
      '${dual.motionEvidenceAtMs ?? ''},${dual.eyeDescentAtMs ?? ''},'
      '${dual.drowsyConfirmed}'
      '${enablePresenceContext ? ',${dual.disappearance!.state.name},${dual.disappearance!.reason},${dual.disappearance!.faceMissingMs},${dual.disappearance!.reliableHistory},${dual.disappearance!.sideExit},${dual.disappearance!.relativeDescent},${dual.disappearance!.sleepSupported}' : ''}'
      '${enableHeadScoreSum ? ',${dual.headScore!.state.name},${dual.headScore!.scoreUsed ?? ''},${dual.headScore!.scoreImputed},${dual.headScore!.scoreSum ?? ''},${dual.headScore!.scoreWindowSamples},${dual.headScore!.measuredHighSamples}' : ''}',
    );
    comparisonFrames.add(
      VisionLabFrame(
        frameIndex: frame.frameIndex,
        timestampMs: frame.timestampMs,
        rawState: dual.finalState,
      ),
    );
    states.add(dual.finalState);
  }
  final report = buildDualTrackLabReport(
    frames: comparisonFrames,
    states: states,
    truth: truth,
    windowMs: windowMs,
  );
  // Derive the run ID from the input, never from wall-clock time.
  final inputName = File(featurePath).uri.pathSegments.last;
  final inputRunId = inputName
      .replaceFirst(RegExp(r'\.csv$', caseSensitive: false), '')
      .replaceFirst(RegExp(r'^frame_features_'), '')
      .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  final runId =
      '$inputRunId${enablePresenceContext ? '_presence' : ''}'
      '${enableHeadScoreSum ? '_headsum' : ''}';
  final directory = Directory(outputDirectory);
  final files = [
    for (final kind in ['frames', 'events', 'metrics'])
      File(
        '${directory.path}${Platform.pathSeparator}'
        'dual_track_${kind}_${windowMs}_$runId.csv',
      ),
  ];
  for (final file in files) {
    if (await file.exists()) {
      throw FileSystemException(
        'Refusing to overwrite existing output',
        file.path,
      );
    }
  }
  await directory.create(recursive: true);
  await files[0].writeAsString('${outputLines.join('\n')}\n', flush: true);
  await writeVisionLabEvents(files[1].path, report.events);
  await files[2].writeAsString(
    '${report.metrics.keys.join(',')}\n${report.metrics.values.join(',')}\n',
    flush: true,
  );
  return files.map((file) => file.path).toList(growable: false);
}
