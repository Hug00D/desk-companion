import 'dart:io';

import 'package:desk_companion/vision/companion_state_evaluator.dart';
import 'package:desk_companion/vision/vision_lab_replay.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 3) {
    stderr.writeln(
      'Usage: dart run tool/vision_lab_replay_companion.dart '
      '<frame_features.csv> <sleeping_ground_truth.csv> <output.csv>',
    );
    exitCode = 64;
    return;
  }

  final featureRows = await readVisionLabReplayCsv(arguments[0]);
  final truthRows = await readVisionLabReplayCsv(arguments[1]);
  final output = File(arguments[2]);
  final truth = _readTruth(truthRows);
  final replay = VisionLabCompanionReplay();
  final frames = <_ReplayFrame>[];
  final outputLines = <String>[visionLabReplayHeader];
  for (final frame in parseVisionLabReplayFrames(featureRows)) {
    final analysis = replay.evaluate(frame);
    frames.add(
      _ReplayFrame(
        timestampMs: frame.timestampMs,
        isSleeping: analysis.status == CompanionStatus.sleeping,
      ),
    );
    outputLines.add(visionLabReplayRow(frame, analysis));
  }

  await output.writeAsString('${outputLines.join('\n')}\n');
  final metrics = _evaluate(frames, truth);
  stdout.writeln('frames=${frames.length}');
  stdout.writeln('accuracy=${metrics.accuracy.toStringAsFixed(6)}');
  stdout.writeln('precision=${metrics.precision.toStringAsFixed(6)}');
  stdout.writeln('recall=${metrics.recall.toStringAsFixed(6)}');
  stdout.writeln('f1=${metrics.f1.toStringAsFixed(6)}');
  stdout.writeln('tp_frames=${metrics.truePositiveFrames}');
  stdout.writeln('fp_frames=${metrics.falsePositiveFrames}');
  stdout.writeln('fn_frames=${metrics.falseNegativeFrames}');
  stdout.writeln('matched_sleep_events=${metrics.matchedEvents}');
  stdout.writeln('true_sleep_events=${metrics.trueEvents}');
  stdout.writeln('false_positive_events=${metrics.falsePositiveEvents}');
  stdout.writeln('missed_events=${metrics.missedEvents}');
  stdout.writeln(
    'onset_delays_ms=${metrics.onsetDelaysMs.isEmpty ? 'n/a' : metrics.onsetDelaysMs.join('/')}',
  );
  stdout.writeln('output=${output.path}');
}

List<_TruthEvent> _readTruth(List<List<String>> rows) {
  if (rows.isEmpty || rows.first.join(',') != 'state,start_ms,end_ms') {
    throw const FormatException(
      'Ground Truth header must be state,start_ms,end_ms.',
    );
  }
  return <_TruthEvent>[
    for (var index = 1; index < rows.length; index++)
      _TruthEvent(
        sleeping: switch (rows[index][0]) {
          'sleeping' => true,
          'normal' => false,
          final value => throw FormatException(
            'Unknown Ground Truth state "$value".',
          ),
        },
        startMs: int.parse(rows[index][1]),
        endMs: int.parse(rows[index][2]),
      ),
  ];
}

_ReplayMetrics _evaluate(List<_ReplayFrame> frames, List<_TruthEvent> truth) {
  var tp = 0;
  var fp = 0;
  var fn = 0;
  var tn = 0;
  for (final frame in frames) {
    final expected = truth
        .firstWhere(
          (event) =>
              frame.timestampMs >= event.startMs &&
              frame.timestampMs < event.endMs,
        )
        .sleeping;
    if (frame.isSleeping && expected) {
      tp++;
    } else if (frame.isSleeping) {
      fp++;
    } else if (expected) {
      fn++;
    } else {
      tn++;
    }
  }

  final predictedEvents = _collapse(frames);
  final trueEvents = truth.where((event) => event.sleeping).toList();
  final usedPredictions = <int>{};
  final delays = <int>[];
  for (final expected in trueEvents) {
    for (var index = 0; index < predictedEvents.length; index++) {
      if (usedPredictions.contains(index)) continue;
      final predicted = predictedEvents[index];
      final overlaps =
          predicted.startMs < expected.endMs &&
          predicted.endMs > expected.startMs;
      if (!overlaps) continue;
      usedPredictions.add(index);
      delays.add(predicted.startMs - expected.startMs);
      break;
    }
  }
  final precision = tp + fp == 0 ? 0.0 : tp / (tp + fp);
  final recall = tp + fn == 0 ? 0.0 : tp / (tp + fn);
  return _ReplayMetrics(
    accuracy: (tp + tn) / frames.length,
    precision: precision,
    recall: recall,
    f1: precision + recall == 0
        ? 0
        : 2 * precision * recall / (precision + recall),
    truePositiveFrames: tp,
    falsePositiveFrames: fp,
    falseNegativeFrames: fn,
    matchedEvents: delays.length,
    trueEvents: trueEvents.length,
    falsePositiveEvents: predictedEvents.length - usedPredictions.length,
    missedEvents: trueEvents.length - delays.length,
    onsetDelaysMs: delays,
  );
}

List<_PredictedEvent> _collapse(List<_ReplayFrame> frames) {
  final events = <_PredictedEvent>[];
  int? startMs;
  for (var index = 0; index < frames.length; index++) {
    if (frames[index].isSleeping && startMs == null) {
      startMs = frames[index].timestampMs;
    }
    if (!frames[index].isSleeping && startMs != null) {
      events.add(
        _PredictedEvent(startMs: startMs, endMs: frames[index].timestampMs),
      );
      startMs = null;
    }
  }
  if (startMs != null) {
    events.add(
      _PredictedEvent(startMs: startMs, endMs: frames.last.timestampMs + 1),
    );
  }
  return events;
}

class _ReplayFrame {
  const _ReplayFrame({required this.timestampMs, required this.isSleeping});

  final int timestampMs;
  final bool isSleeping;
}

class _TruthEvent {
  const _TruthEvent({
    required this.sleeping,
    required this.startMs,
    required this.endMs,
  });

  final bool sleeping;
  final int startMs;
  final int endMs;
}

class _PredictedEvent {
  const _PredictedEvent({required this.startMs, required this.endMs});

  final int startMs;
  final int endMs;
}

class _ReplayMetrics {
  const _ReplayMetrics({
    required this.accuracy,
    required this.precision,
    required this.recall,
    required this.f1,
    required this.truePositiveFrames,
    required this.falsePositiveFrames,
    required this.falseNegativeFrames,
    required this.matchedEvents,
    required this.trueEvents,
    required this.falsePositiveEvents,
    required this.missedEvents,
    required this.onsetDelaysMs,
  });

  final double accuracy;
  final double precision;
  final double recall;
  final double f1;
  final int truePositiveFrames;
  final int falsePositiveFrames;
  final int falseNegativeFrames;
  final int matchedEvents;
  final int trueEvents;
  final int falsePositiveEvents;
  final int missedEvents;
  final List<int> onsetDelaysMs;
}
