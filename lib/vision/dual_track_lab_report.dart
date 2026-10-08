import 'dart:math' as math;

import 'vision_lab_comparison.dart';

class DualTrackLabReport {
  const DualTrackLabReport({required this.events, required this.metrics});

  final List<VisionLabEvent> events;
  final Map<String, String> metrics;
}

DualTrackLabReport buildDualTrackLabReport({
  required List<VisionLabFrame> frames,
  required List<String> states,
  required List<VisionLabEvent> truth,
  required int windowMs,
}) {
  const supportedTruth = {'normal', 'reading', 'sleeping'};
  if (truth.any((event) => !supportedTruth.contains(event.state))) {
    throw const FormatException(
      'This development report accepts only '
      'normal, reading, sleeping Ground Truth; other labels need review.',
    );
  }
  if (frames.isEmpty || frames.length != states.length) {
    throw ArgumentError('Frames and states must be non-empty and aligned.');
  }
  final durations = [
    for (var i = 1; i < frames.length; i++)
      frames[i].timestampMs - frames[i - 1].timestampMs,
  ]..sort();
  final tailMs = durations.isEmpty ? 1 : durations[durations.length ~/ 2];
  final endMs = math.min(truth.last.endMs, frames.last.timestampMs + tailMs);
  final events = collapseVisionLabEvents(
    frames: frames,
    states: states,
    videoEndMs: endMs,
  );
  bool positive(String state) =>
      const {'drowsy_like', 'posture_down', 'sleeping'}.contains(state);
  final binaryStates = states
      .map((s) => positive(s) ? 'sleeping' : 'normal')
      .toList(growable: false);
  final binaryTruth = truth
      .map(
        (e) => VisionLabEvent(
          state: e.state == 'sleeping' ? 'sleeping' : 'normal',
          startMs: e.startMs,
          endMs: e.endMs,
        ),
      )
      .toList(growable: false);
  final binaryEvents = collapseVisionLabEvents(
    frames: frames,
    states: binaryStates,
    videoEndMs: endMs,
  );
  final eventMetrics = evaluateVisionLabStrategy(
    frames: frames,
    frameStates: binaryStates,
    predictedEvents: binaryEvents,
    groundTruthEvents: binaryTruth,
  );
  var tp = 0;
  var fp = 0;
  var fn = 0;
  var tn = 0;
  var readingFalseFrames = 0;
  var unknownFrames = 0;
  for (var i = 0; i < frames.length; i++) {
    final expected = groundTruthStateAt(truth, frames[i].timestampMs);
    final predicted = positive(states[i]);
    if (predicted && expected == 'sleeping') {
      tp++;
    } else if (predicted) {
      fp++;
      if (expected == 'reading') readingFalseFrames++;
    } else if (expected == 'sleeping') {
      fn++;
    } else {
      tn++;
    }
    if (states[i] == 'unknown_low_head') unknownFrames++;
  }
  final delays = <int>[];
  final available = binaryEvents.where((e) => e.state == 'sleeping').toList();
  for (final expected in truth.where((e) => e.state == 'sleeping')) {
    final match = available.indexWhere(
      (e) => e.startMs < expected.endMs && e.endMs > expected.startMs,
    );
    if (match >= 0) {
      delays.add(available.removeAt(match).startMs - expected.startMs);
    }
  }
  final hasReading = truth.any((e) => e.state == 'reading');
  final readingFalseEvents = binaryEvents
      .where(
        (e) =>
            e.state == 'sleeping' &&
            truth.any(
              (t) =>
                  t.state == 'reading' &&
                  e.startMs < t.endMs &&
                  e.endMs > t.startMs,
            ),
      )
      .length;
  final unknownDurations = events
      .where((e) => e.state == 'unknown_low_head')
      .map((e) => e.endMs - e.startMs);
  final precision = tp + fp == 0 ? 0.0 : tp / (tp + fp);
  final recall = tp + fn == 0 ? 0.0 : tp / (tp + fn);
  final eventPrecision =
      eventMetrics.matchedEvents + eventMetrics.falsePositiveEvents == 0
      ? 0.0
      : eventMetrics.matchedEvents /
            (eventMetrics.matchedEvents + eventMetrics.falsePositiveEvents);
  final eventRecall = eventMetrics.trueEvents == 0
      ? 0.0
      : eventMetrics.matchedEvents / eventMetrics.trueEvents;
  double f1(double p, double r) => p + r == 0 ? 0 : 2 * p * r / (p + r);
  return DualTrackLabReport(
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
      'matched_sleep_events': '${eventMetrics.matchedEvents}',
      'true_sleep_events': '${eventMetrics.trueEvents}',
      'false_positive_events': '${eventMetrics.falsePositiveEvents}',
      'missed_events': '${eventMetrics.missedEvents}',
      'state_switches': '${math.max(0, events.length - 1)}',
      'onset_delays_ms': delays.join(';'),
      'reading_labels_available': '$hasReading',
      'reading_fp_frames': hasReading ? '$readingFalseFrames' : '',
      'reading_fp_events': hasReading ? '$readingFalseEvents' : '',
      'unknown_low_head_frames': '$unknownFrames',
      'unknown_low_head_ratio': (unknownFrames / frames.length).toStringAsFixed(
        6,
      ),
      'unknown_low_head_longest_ms':
          '${unknownDurations.isEmpty ? 0 : unknownDurations.reduce(math.max)}',
    },
  );
}
