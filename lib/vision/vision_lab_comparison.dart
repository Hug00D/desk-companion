import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

const String visionLabNormalState = 'normal';

class VisionLabFrame {
  const VisionLabFrame({
    required this.frameIndex,
    required this.timestampMs,
    required this.rawState,
  });

  final int frameIndex;
  final int timestampMs;
  final String rawState;
}

class VisionLabEvent {
  const VisionLabEvent({
    required this.state,
    required this.startMs,
    required this.endMs,
  });

  final String state;
  final int startMs;
  final int endMs;
}

class VisionLabStrategyResult {
  const VisionLabStrategyResult({
    required this.strategy,
    required this.frameStates,
    required this.events,
    required this.metrics,
  });

  final String strategy;
  final List<String> frameStates;
  final List<VisionLabEvent> events;
  final VisionLabMetrics metrics;
}

class VisionLabMetrics {
  const VisionLabMetrics({
    required this.frameAccuracy,
    required this.falsePositiveEvents,
    required this.falsePositiveEventsByState,
    required this.missedEvents,
    required this.stateSwitches,
    required this.matchedEvents,
    required this.trueEvents,
    required this.averageDelayMs,
  });

  final double frameAccuracy;
  final int falsePositiveEvents;
  final Map<String, int> falsePositiveEventsByState;
  final int missedEvents;
  final int stateSwitches;
  final int matchedEvents;
  final int trueEvents;
  final double? averageDelayMs;
}

class VisionLabComparisonOutput {
  const VisionLabComparisonOutput({
    required this.singleFrame,
    required this.threeOfFive,
    required this.videoEndMs,
  });

  final VisionLabStrategyResult singleFrame;
  final VisionLabStrategyResult threeOfFive;
  final int videoEndMs;
}

List<String> applySingleFrame(List<VisionLabFrame> frames) {
  return frames.map((frame) => frame.rawState).toList(growable: false);
}

/// Applies a causal 3-of-5 vote to raw per-frame states.
///
/// Only the current and four preceding rows are considered. An incomplete
/// startup window or a full window without three equal votes resolves to
/// `normal`. There is intentionally no latch, hysteresis, or cooldown.
List<String> applyThreeOfFive(List<VisionLabFrame> frames) {
  final output = <String>[];
  for (var index = 0; index < frames.length; index++) {
    if (index < 4) {
      output.add(visionLabNormalState);
      continue;
    }

    final votes = <String, int>{};
    for (var windowIndex = index - 4; windowIndex <= index; windowIndex++) {
      final state = frames[windowIndex].rawState;
      votes[state] = (votes[state] ?? 0) + 1;
    }
    String? winner;
    for (final entry in votes.entries) {
      if (entry.value >= 3) {
        winner = entry.key;
        break;
      }
    }
    output.add(winner ?? visionLabNormalState);
  }
  return output;
}

List<VisionLabEvent> collapseVisionLabEvents({
  required List<VisionLabFrame> frames,
  required List<String> states,
  required int videoEndMs,
}) {
  if (frames.length != states.length) {
    throw ArgumentError('frames and states must have the same length.');
  }
  if (frames.isEmpty) return const <VisionLabEvent>[];

  final events = <VisionLabEvent>[];
  var currentState = states.first;
  var startMs = frames.first.timestampMs;
  for (var index = 1; index < frames.length; index++) {
    if (states[index] == currentState) continue;
    events.add(
      VisionLabEvent(
        state: currentState,
        startMs: startMs,
        endMs: frames[index].timestampMs,
      ),
    );
    currentState = states[index];
    startMs = frames[index].timestampMs;
  }
  events.add(
    VisionLabEvent(state: currentState, startMs: startMs, endMs: videoEndMs),
  );
  return events;
}

VisionLabMetrics evaluateVisionLabStrategy({
  required List<VisionLabFrame> frames,
  required List<String> frameStates,
  required List<VisionLabEvent> predictedEvents,
  required List<VisionLabEvent> groundTruthEvents,
}) {
  if (frames.length != frameStates.length || frames.isEmpty) {
    throw ArgumentError(
      'frames and frameStates must be non-empty and aligned.',
    );
  }

  var exactFrameMatches = 0;
  for (var index = 0; index < frames.length; index++) {
    final truth = groundTruthStateAt(
      groundTruthEvents,
      frames[index].timestampMs,
    );
    if (frameStates[index] == truth) exactFrameMatches++;
  }

  final truePositiveEvents = groundTruthEvents
      .where((event) => event.state != visionLabNormalState)
      .toList(growable: false);
  final predictedPositiveEvents = predictedEvents
      .where((event) => event.state != visionLabNormalState)
      .toList(growable: false);
  final availablePredictions = <int>{
    for (var index = 0; index < predictedPositiveEvents.length; index++) index,
  };
  final delays = <int>[];

  for (final truth in truePositiveEvents) {
    int? selectedIndex;
    var earliestDetectionMs = 1 << 62;
    for (final predictionIndex in availablePredictions) {
      final prediction = predictedPositiveEvents[predictionIndex];
      if (prediction.state != truth.state) continue;
      final overlapMs = math.max(
        0,
        math.min(prediction.endMs, truth.endMs) -
            math.max(prediction.startMs, truth.startMs),
      );
      if (overlapMs <= 0) continue;
      final detectionMs = math.max(prediction.startMs, truth.startMs);
      if (detectionMs < earliestDetectionMs) {
        earliestDetectionMs = detectionMs;
        selectedIndex = predictionIndex;
      }
    }
    if (selectedIndex != null) {
      final prediction = predictedPositiveEvents[selectedIndex];
      availablePredictions.remove(selectedIndex);
      delays.add(prediction.startMs - truth.startMs);
    }
  }

  final falsePositiveEventsByState = <String, int>{};
  for (final predictionIndex in availablePredictions) {
    final state = predictedPositiveEvents[predictionIndex].state;
    falsePositiveEventsByState[state] =
        (falsePositiveEventsByState[state] ?? 0) + 1;
  }

  return VisionLabMetrics(
    frameAccuracy: exactFrameMatches / frames.length,
    falsePositiveEvents: availablePredictions.length,
    falsePositiveEventsByState: Map.unmodifiable(falsePositiveEventsByState),
    missedEvents: truePositiveEvents.length - delays.length,
    stateSwitches: math.max(0, predictedEvents.length - 1),
    matchedEvents: delays.length,
    trueEvents: truePositiveEvents.length,
    averageDelayMs: delays.isEmpty
        ? null
        : delays.reduce((left, right) => left + right) / delays.length,
  );
}

String groundTruthStateAt(List<VisionLabEvent> events, int timestampMs) {
  for (var index = 0; index < events.length; index++) {
    final event = events[index];
    final isLastBoundary =
        index == events.length - 1 && timestampMs == event.endMs;
    if (timestampMs >= event.startMs &&
        (timestampMs < event.endMs || isLastBoundary)) {
      return event.state;
    }
  }
  throw StateError('No Ground Truth state at $timestampMs ms.');
}

Future<VisionLabComparisonOutput> compareVisionLabCsv({
  required String featurePath,
  required String groundTruthPath,
}) async {
  final frames = await readVisionLabFrames(featurePath);
  final groundTruth = await readGroundTruthEvents(groundTruthPath);
  if (frames.isEmpty) throw const FormatException('Feature CSV has no rows.');

  final medianFrameDurationMs = _medianFrameDuration(frames);
  final videoEndMs = math.max(
    groundTruth.last.endMs,
    frames.last.timestampMs + medianFrameDurationMs,
  );
  final singleStates = applySingleFrame(frames);
  final votedStates = applyThreeOfFive(frames);
  final singleEvents = collapseVisionLabEvents(
    frames: frames,
    states: singleStates,
    videoEndMs: videoEndMs,
  );
  final votedEvents = collapseVisionLabEvents(
    frames: frames,
    states: votedStates,
    videoEndMs: videoEndMs,
  );

  return VisionLabComparisonOutput(
    videoEndMs: videoEndMs,
    singleFrame: VisionLabStrategyResult(
      strategy: 'single_frame',
      frameStates: singleStates,
      events: singleEvents,
      metrics: evaluateVisionLabStrategy(
        frames: frames,
        frameStates: singleStates,
        predictedEvents: singleEvents,
        groundTruthEvents: groundTruth,
      ),
    ),
    threeOfFive: VisionLabStrategyResult(
      strategy: '3_of_5',
      frameStates: votedStates,
      events: votedEvents,
      metrics: evaluateVisionLabStrategy(
        frames: frames,
        frameStates: votedStates,
        predictedEvents: votedEvents,
        groundTruthEvents: groundTruth,
      ),
    ),
  );
}

Future<List<VisionLabFrame>> readVisionLabFrames(String path) async {
  final rows = await _readSimpleCsv(path);
  if (rows.isEmpty) throw const FormatException('Feature CSV is empty.');
  final header = rows.first;
  final frameIndexColumn = header.indexOf('frame_idx');
  final timestampColumn = header.indexOf('timestamp_ms');
  final stateColumn = header.indexOf('raw_state');
  if (frameIndexColumn < 0 || timestampColumn < 0 || stateColumn < 0) {
    throw const FormatException(
      'Feature CSV must contain frame_idx, timestamp_ms, and raw_state.',
    );
  }

  final frames = <VisionLabFrame>[];
  for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
    final row = rows[rowIndex];
    if (row.length != header.length) {
      throw FormatException(
        'Invalid feature column count at row ${rowIndex + 1}.',
      );
    }
    final frameIndex = int.tryParse(row[frameIndexColumn]);
    final timestampMs = int.tryParse(row[timestampColumn]);
    final rawState = row[stateColumn];
    if (frameIndex == null || timestampMs == null || rawState.isEmpty) {
      throw FormatException('Invalid feature row ${rowIndex + 1}.');
    }
    if (frames.isNotEmpty && timestampMs <= frames.last.timestampMs) {
      throw FormatException(
        'timestamp_ms must increase at row ${rowIndex + 1}.',
      );
    }
    frames.add(
      VisionLabFrame(
        frameIndex: frameIndex,
        timestampMs: timestampMs,
        rawState: rawState,
      ),
    );
  }
  return frames;
}

Future<List<VisionLabEvent>> readGroundTruthEvents(String path) async {
  final rows = await _readSimpleCsv(path);
  if (rows.isEmpty || rows.first.join(',') != 'state,start_ms,end_ms') {
    throw const FormatException(
      'Ground Truth CSV must have state,start_ms,end_ms header.',
    );
  }

  final events = <VisionLabEvent>[];
  for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
    final row = rows[rowIndex];
    if (row.length != 3) {
      throw FormatException(
        'Invalid Ground Truth column count at row ${rowIndex + 1}.',
      );
    }
    final startMs = int.tryParse(row[1]);
    final endMs = int.tryParse(row[2]);
    if (row[0].isEmpty ||
        startMs == null ||
        endMs == null ||
        endMs <= startMs) {
      throw FormatException('Invalid Ground Truth row ${rowIndex + 1}.');
    }
    if (events.isNotEmpty && startMs != events.last.endMs) {
      throw FormatException(
        'Ground Truth must be contiguous at row ${rowIndex + 1}.',
      );
    }
    events.add(VisionLabEvent(state: row[0], startMs: startMs, endMs: endMs));
  }
  if (events.isEmpty) {
    throw const FormatException('Ground Truth CSV has no events.');
  }
  return events;
}

Future<void> writeVisionLabEvents(
  String path,
  List<VisionLabEvent> events,
) async {
  final rows = <String>['state,start_ms,end_ms'];
  rows.addAll(
    events.map((event) => '${event.state},${event.startMs},${event.endMs}'),
  );
  await File(path).writeAsString('${rows.join('\n')}\n', flush: true);
}

Future<void> writeVisionLabMetrics(
  String path,
  List<VisionLabStrategyResult> results,
) async {
  final rows = <String>[
    'strategy,frame_accuracy,false_positive_events,missed_events,'
        'state_switches,matched_events,true_events,average_delay_ms,'
        'eye_closed_false_positive_events,'
        'head_turned_false_positive_events,'
        'posture_down_false_positive_events,'
        'user_missing_false_positive_events',
  ];
  for (final result in results) {
    final metrics = result.metrics;
    rows.add(
      '${result.strategy},${metrics.frameAccuracy.toStringAsFixed(6)},'
      '${metrics.falsePositiveEvents},${metrics.missedEvents},'
      '${metrics.stateSwitches},${metrics.matchedEvents},'
      '${metrics.trueEvents},${metrics.averageDelayMs?.toStringAsFixed(3) ?? ''},'
      '${metrics.falsePositiveEventsByState['eye_closed'] ?? 0},'
      '${metrics.falsePositiveEventsByState['head_turned'] ?? 0},'
      '${metrics.falsePositiveEventsByState['posture_down'] ?? 0},'
      '${metrics.falsePositiveEventsByState['user_missing'] ?? 0}',
    );
  }
  await File(path).writeAsString('${rows.join('\n')}\n', flush: true);
}

Future<List<List<String>>> _readSimpleCsv(String path) async {
  final content = await File(path).readAsString();
  return const LineSplitter()
      .convert(content)
      .where((line) => line.trim().isNotEmpty)
      .map((line) => line.split(','))
      .toList(growable: false);
}

int _medianFrameDuration(List<VisionLabFrame> frames) {
  if (frames.length < 2) return 1;
  final durations = <int>[
    for (var index = 1; index < frames.length; index++)
      frames[index].timestampMs - frames[index - 1].timestampMs,
  ]..sort();
  return durations[durations.length ~/ 2];
}
