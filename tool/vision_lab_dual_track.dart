import 'dart:io';

import 'package:desk_companion/vision/dual_track_context_classifier.dart';
import 'package:desk_companion/vision/dual_track_lab_report.dart';
import 'package:desk_companion/vision/posture_down_detector.dart';
import 'package:desk_companion/vision/sleep_first_lab_report.dart';
import 'package:desk_companion/vision/vision_lab_comparison.dart';
import 'package:desk_companion/vision/vision_lab_replay.dart';
import 'package:desk_companion/vision/vision_result.dart';

const _usage =
    'Usage: dart run tool/vision_lab_dual_track.dart '
    '<frame_features.csv> <sleeping_ground_truth.csv> <output_directory> '
    '--window-ms=2000|--window-ms=3000 '
    '[--presence-context [--head-score-sum]] [--long-short-gate] '
    '[--sleep-first] [--person-presence=<person_presence_litert.csv>]';

Future<void> main(List<String> arguments) async {
  final options = arguments.skip(4).toList(growable: false);
  final flags = options
      .where((option) => !option.startsWith('--person-presence='))
      .toSet();
  final presenceOptions = options
      .where((option) => option.startsWith('--person-presence='))
      .toList(growable: false);
  final personPresencePath = presenceOptions.length == 1
      ? presenceOptions.single.substring('--person-presence='.length)
      : null;
  if (arguments.length < 4 ||
      arguments.length > 9 ||
      options.toSet().length != options.length ||
      presenceOptions.length > 1 ||
      (personPresencePath != null && personPresencePath.isEmpty) ||
      flags.any(
        (flag) => !const {
          '--presence-context',
          '--head-score-sum',
          '--long-short-gate',
          '--sleep-first',
        }.contains(flag),
      ) ||
      (flags.contains('--head-score-sum') &&
          !flags.contains('--presence-context')) ||
      (personPresencePath != null &&
          (!flags.contains('--sleep-first') ||
              !flags.contains('--presence-context'))) ||
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
      enableLongShortGate: flags.contains('--long-short-gate'),
      enableSleepFirst: flags.contains('--sleep-first'),
      personPresencePath: personPresencePath,
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
  bool enableLongShortGate = false,
  bool enableSleepFirst = false,
  String? personPresencePath,
}) async {
  if (personPresencePath != null &&
      (!enableSleepFirst || !enablePresenceContext)) {
    throw ArgumentError(
      'Person-presence replay requires sleep-first and presence context.',
    );
  }
  final classifier = DualTrackContextClassifier(
    windowMs: windowMs,
    enablePresenceContext: enablePresenceContext,
    enableHeadScoreSum: enableHeadScoreSum,
    enableLongShortGate: enableLongShortGate,
    enableSleepFirstTrackingLoss:
        enableSleepFirst && personPresencePath != null,
  );
  final frames = parseVisionLabReplayFrames(
    await readVisionLabReplayCsv(featurePath),
    requireRawEyeClosed: true,
  );
  final truth = await readGroundTruthEvents(truthPath);
  final personPresenceSamples = personPresencePath == null
      ? const <int, _PersonPresenceSample>{}
      : await _readPersonPresenceSamples(personPresencePath);
  final replay = VisionLabCompanionReplay();
  final outputLines = <String>[
    'frame_idx,timestamp_ms,fast_status,fast_cause,low_head_candidate,'
        'slow_state,slow_window_ms,evidence_eye,evidence_motion,evidence_posture,'
        'data_quality,final_state,configured_window_ms,eye_coverage,pose_coverage,'
        'closed_duration_ms,nose_drop,pitch_range,nose_range,'
        'motion_evidence_at_ms,eye_descent_at_ms,drowsy_confirmed'
        '${enableLongShortGate ? ',long_context,short_trigger,sleep_latched,sleep_latch_source,posture_score,static_deep_posture_ms,continuous_tracking_loss_ms' : ''}'
        '${enablePresenceContext ? ',presence_context,presence_reason,face_missing_ms,loss_history_reliable,side_exit_evidence,relative_descent_evidence,sleep_supported' : ''}'
        '${enableHeadScoreSum ? ',head_score_state,head_score_used,head_score_imputed,head_score_sum,head_score_samples,head_score_measured_high_samples' : ''}'
        '${enableSleepFirst ? ',sleep_first_state' : ''}'
        '${personPresencePath != null ? ',person_presence_sampled,person_present,person_mask_area_ratio' : ''}',
  ];
  final comparisonFrames = <VisionLabFrame>[];
  final states = <String>[];
  final sleepFirstStates = <String>[];
  _PersonPresenceSample? latestPersonPresence;
  for (final sourceFrame in frames) {
    if (sourceFrame.result.hasFace || sourceFrame.result.hasPose) {
      latestPersonPresence = null;
    } else {
      latestPersonPresence =
          personPresenceSamples[sourceFrame.timestampMs] ??
          latestPersonPresence;
    }
    final frame = latestPersonPresence == null
        ? sourceFrame
        : VisionLabReplayFrame(
            frameIndex: sourceFrame.frameIndex,
            timestampMs: sourceFrame.timestampMs,
            rawEyeClosed: sourceFrame.rawEyeClosed,
            result: _withPersonPresence(
              sourceFrame.result,
              latestPersonPresence,
            ),
          );
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
      postureScore: fast.postureDownResult.isCalibrating
          ? null
          : fast.postureDownResult.score,
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
      '${enableLongShortGate ? ',${dual.longContext.csvValue},${dual.shortTrigger},${dual.sleepLatched},${dual.sleepLatchSource},${dual.postureScore ?? ''},${dual.staticDeepPostureMs},${dual.continuousTrackingLossMs}' : ''}'
      '${enablePresenceContext ? ',${dual.disappearance!.state.name},${dual.disappearance!.reason},${dual.disappearance!.faceMissingMs},${dual.disappearance!.reliableHistory},${dual.disappearance!.sideExit},${dual.disappearance!.relativeDescent},${dual.disappearance!.sleepSupported}' : ''}'
      '${enableHeadScoreSum ? ',${dual.headScore!.state.name},${dual.headScore!.scoreUsed ?? ''},${dual.headScore!.scoreImputed},${dual.headScore!.scoreSum ?? ''},${dual.headScore!.scoreWindowSamples},${dual.headScore!.measuredHighSamples}' : ''}'
      '${enableSleepFirst ? ',${_sleepFirstState(dual)}' : ''}'
      '${personPresencePath != null ? ',${frame.result.personPresenceSampled},${frame.result.personPresent ?? ''},${frame.result.personMaskAreaRatio ?? ''}' : ''}',
    );
    comparisonFrames.add(
      VisionLabFrame(
        frameIndex: frame.frameIndex,
        timestampMs: frame.timestampMs,
        rawState: dual.finalState,
      ),
    );
    states.add(dual.finalState);
    sleepFirstStates.add(_sleepFirstState(dual));
  }
  late final List<VisionLabEvent> reportEvents;
  late final Map<String, String> reportMetrics;
  if (enableSleepFirst) {
    final report = buildSleepFirstLabReport(
      frames: comparisonFrames,
      states: sleepFirstStates,
      truth: truth,
      windowMs: windowMs,
    );
    reportEvents = report.events;
    reportMetrics = report.metrics;
  } else {
    final report = buildDualTrackLabReport(
      frames: comparisonFrames,
      states: states,
      truth: truth,
      windowMs: windowMs,
    );
    reportEvents = report.events;
    reportMetrics = report.metrics;
  }
  // Derive the run ID from the input, never from wall-clock time.
  final inputName = File(featurePath).uri.pathSegments.last;
  final inputRunId = inputName
      .replaceFirst(RegExp(r'\.csv$', caseSensitive: false), '')
      .replaceFirst(RegExp(r'^frame_features_'), '')
      .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  final runId =
      '$inputRunId${enablePresenceContext ? '_presence' : ''}'
      '${enableHeadScoreSum ? '_headsum' : ''}'
      '${enableLongShortGate ? '_longshort' : ''}';
  final replayRunId = '$runId${personPresencePath != null ? '_mask' : ''}';
  final outputPrefix = enableSleepFirst ? 'sleep_first' : 'dual_track';
  final directory = Directory(outputDirectory);
  final files = [
    for (final kind in ['frames', 'events', 'metrics'])
      File(
        '${directory.path}${Platform.pathSeparator}'
        '${outputPrefix}_${kind}_${windowMs}_'
        '$replayRunId${enableSleepFirst ? '_sleepfirst' : ''}.csv',
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
  await writeVisionLabEvents(files[1].path, reportEvents);
  await files[2].writeAsString(
    '${reportMetrics.keys.join(',')}\n${reportMetrics.values.join(',')}\n',
    flush: true,
  );
  return files.map((file) => file.path).toList(growable: false);
}

Future<Map<int, _PersonPresenceSample>> _readPersonPresenceSamples(
  String path,
) async {
  final rows = await readVisionLabReplayCsv(path);
  if (rows.length < 2) {
    throw const FormatException('Person-presence CSV has no samples.');
  }
  final header = rows.first;
  const required = {
    'timestamp_ms',
    'person_mask_mean_confidence',
    'person_mask_area_ratio',
    'inference_ms',
  };
  if (!header.toSet().containsAll(required)) {
    throw const FormatException('Person-presence CSV is missing columns.');
  }
  final indexes = {
    for (var index = 0; index < header.length; index++) header[index]: index,
  };
  final samples = <int, _PersonPresenceSample>{};
  for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
    final row = rows[rowIndex];
    if (row.length != header.length) {
      throw FormatException(
        'Invalid person-presence column count at row ${rowIndex + 1}.',
      );
    }
    final timestampMs = int.tryParse(row[indexes['timestamp_ms']!]);
    final areaRatio = double.tryParse(row[indexes['person_mask_area_ratio']!]);
    final meanConfidence = double.tryParse(
      row[indexes['person_mask_mean_confidence']!],
    );
    final inferenceMs = double.tryParse(row[indexes['inference_ms']!]);
    if (timestampMs == null ||
        timestampMs < 0 ||
        areaRatio == null ||
        !areaRatio.isFinite ||
        meanConfidence == null ||
        !meanConfidence.isFinite ||
        inferenceMs == null ||
        !inferenceMs.isFinite ||
        samples.containsKey(timestampMs)) {
      throw FormatException('Invalid person-presence row ${rowIndex + 1}.');
    }
    samples[timestampMs] = _PersonPresenceSample(
      present: areaRatio >= 0.10,
      areaRatio: areaRatio,
      meanConfidence: meanConfidence,
      inferenceMs: inferenceMs,
    );
  }
  return samples;
}

VisionResult _withPersonPresence(
  VisionResult result,
  _PersonPresenceSample sample,
) {
  final raw = Map<dynamic, dynamic>.of(result.raw)
    ..['personPresenceSampled'] = true
    ..['personPresent'] = sample.present
    ..['personMaskAreaRatio'] = sample.areaRatio
    ..['personMaskMeanConfidence'] = sample.meanConfidence
    ..['personPresenceInferenceMs'] = sample.inferenceMs;
  return VisionResult.fromNativeMap(raw);
}

class _PersonPresenceSample {
  const _PersonPresenceSample({
    required this.present,
    required this.areaRatio,
    required this.meanConfidence,
    required this.inferenceMs,
  });

  final bool present;
  final double areaRatio;
  final double meanConfidence;
  final double inferenceMs;
}

String _sleepFirstState(DualTrackContextResult result) {
  if (const {'drowsy_like', 'sleeping'}.contains(result.finalState) ||
      result.finalState == 'posture_down' && result.sleepLatched) {
    return sleepFirstSleepingState;
  }
  if (result.lowHeadCandidate ||
      result.slowState != SlowContextState.none ||
      const {'reading_like', 'unknown_low_head'}.contains(result.finalState)) {
    return sleepFirstUncertainState;
  }
  return sleepFirstOtherState;
}
