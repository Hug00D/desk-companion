import 'dart:math' as math;

import 'vision_lab_comparison.dart';

const sleepFirstSleepingState = 'sleeping';
const sleepFirstUncertainState = 'uncertain_low_head';
const sleepFirstOtherState = 'other';

class SleepFirstLabReport {
  const SleepFirstLabReport({required this.events, required this.metrics});

  final List<VisionLabEvent> events;
  final Map<String, String> metrics;
}

SleepFirstLabReport buildSleepFirstLabReport({
  required List<VisionLabFrame> frames,
  required List<String> states,
  required List<VisionLabEvent> truth,
  required int windowMs,
}) {
  const supportedStates = {
    sleepFirstSleepingState,
    sleepFirstUncertainState,
    sleepFirstOtherState,
  };
  const supportedTruth = {'normal', 'reading', 'sleeping'};
  if (frames.isEmpty || frames.length != states.length) {
    throw ArgumentError('Frames and states must be non-empty and aligned.');
  }
  if (states.any((state) => !supportedStates.contains(state))) {
    throw const FormatException(
      'Sleep-first states must be sleeping, uncertain_low_head, or other.',
    );
  }
  if (truth.any((event) => !supportedTruth.contains(event.state))) {
    throw const FormatException(
      'Sleep-first Ground Truth accepts normal, reading, and sleeping only.',
    );
  }

  final frameDurations = [
    for (var i = 1; i < frames.length; i++)
      frames[i].timestampMs - frames[i - 1].timestampMs,
  ]..sort();
  final tailMs = frameDurations.isEmpty
      ? 1
      : frameDurations[frameDurations.length ~/ 2];
  final endMs = math.min(truth.last.endMs, frames.last.timestampMs + tailMs);
  final events = collapseVisionLabEvents(
    frames: frames,
    states: states,
    videoEndMs: endMs,
  );
  final predictedSleepEvents = events
      .where((event) => event.state == sleepFirstSleepingState)
      .toList(growable: false);
  final trueSleepEvents = truth
      .where((event) => event.state == sleepFirstSleepingState)
      .toList(growable: false);

  var tp = 0;
  var fp = 0;
  var fn = 0;
  var tn = 0;
  var uncertainFrames = 0;
  var uncertainSleepFrames = 0;
  for (var i = 0; i < frames.length; i++) {
    final expectedSleeping =
        groundTruthStateAt(truth, frames[i].timestampMs) ==
        sleepFirstSleepingState;
    final predictedSleeping = states[i] == sleepFirstSleepingState;
    if (predictedSleeping && expectedSleeping) {
      tp++;
    } else if (predictedSleeping) {
      fp++;
    } else if (expectedSleeping) {
      fn++;
    } else {
      tn++;
    }
    if (states[i] == sleepFirstUncertainState) {
      uncertainFrames++;
      if (expectedSleeping) uncertainSleepFrames++;
    }
  }

  final delays = <int>[];
  var interruptions = 0;
  for (final expected in trueSleepEvents) {
    final overlaps = predictedSleepEvents
        .where((prediction) => _overlaps(prediction, expected))
        .toList(growable: false);
    if (overlaps.isEmpty) continue;
    final firstDetectionMs = overlaps
        .map((prediction) => math.max(prediction.startMs, expected.startMs))
        .reduce(math.min);
    delays.add(firstDetectionMs - expected.startMs);
    interruptions += math.max(0, overlaps.length - 1);
  }
  final falseSleepEvents = predictedSleepEvents
      .where(
        (prediction) =>
            !trueSleepEvents.any((expected) => _overlaps(prediction, expected)),
      )
      .length;

  final uncertainDurations = events
      .where((event) => event.state == sleepFirstUncertainState)
      .map((event) => event.endMs - event.startMs)
      .toList(growable: false);
  final precision = tp + fp == 0 ? 0.0 : tp / (tp + fp);
  final recall = tp + fn == 0 ? 0.0 : tp / (tp + fn);
  final eventPrecision = predictedSleepEvents.isEmpty
      ? 0.0
      : (predictedSleepEvents.length - falseSleepEvents) /
            predictedSleepEvents.length;
  final eventRecall = trueSleepEvents.isEmpty
      ? 0.0
      : delays.length / trueSleepEvents.length;
  final averageDelayMs = delays.isEmpty
      ? null
      : delays.reduce((a, b) => a + b) / delays.length;
  double f1(double p, double r) => p + r == 0 ? 0 : 2 * p * r / (p + r);

  return SleepFirstLabReport(
    events: events,
    metrics: {
      'window_ms': '$windowMs',
      'frames': '${frames.length}',
      'tp_frames': '$tp',
      'fp_frames': '$fp',
      'fn_frames': '$fn',
      'tn_frames': '$tn',
      'precision': precision.toStringAsFixed(6),
      'recall': recall.toStringAsFixed(6),
      'f1': f1(precision, recall).toStringAsFixed(6),
      'event_precision': eventPrecision.toStringAsFixed(6),
      'event_recall': eventRecall.toStringAsFixed(6),
      'event_f1': f1(eventPrecision, eventRecall).toStringAsFixed(6),
      'detected_sleep_events': '${delays.length}',
      'true_sleep_events': '${trueSleepEvents.length}',
      'false_sleep_events': '$falseSleepEvents',
      'missed_sleep_events': '${trueSleepEvents.length - delays.length}',
      'sleep_interruptions': '$interruptions',
      'onset_delays_ms': delays.join(';'),
      'average_onset_delay_ms': averageDelayMs?.toStringAsFixed(3) ?? '',
      'uncertain_low_head_frames': '$uncertainFrames',
      'uncertain_during_sleep_frames': '$uncertainSleepFrames',
      'uncertain_low_head_longest_ms': uncertainDurations.isEmpty
          ? '0'
          : '${uncertainDurations.reduce(math.max)}',
    },
  );
}

bool _overlaps(VisionLabEvent left, VisionLabEvent right) =>
    left.startMs < right.endMs && left.endMs > right.startMs;
