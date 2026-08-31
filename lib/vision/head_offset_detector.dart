import 'one_euro_filter.dart';
import 'vision_result.dart';

enum HeadOffsetState { unavailable, normal, distracted }

class HeadOffsetDetectionResult {
  const HeadOffsetDetectionResult({
    required this.state,
    required this.distractedFrameCount,
  });

  final HeadOffsetState state;
  final int distractedFrameCount;
}

class HeadOffsetDetector {
  HeadOffsetDetector({
    this.enterThreshold = 55,
    this.exitThreshold = 30,
    this.evidenceWindowSize = 5,
    this.enterVotes = 3,
    this.exitFrames = 2,
    this.missingFaceHoldFrames = 2,
    this.settledGazeDuration = const Duration(seconds: 6),
    this.settledGazeSpread = 14,
    this.settledGazeMinSamples = 4,
    this.settledGazeMaxScore = 75,
    OneEuroFilter? scoreFilter,
  }) : scoreFilter = scoreFilter ?? OneEuroFilter(minCutoff: 1.25, beta: 0.08);

  final double enterThreshold;
  final double exitThreshold;
  final int evidenceWindowSize;
  final int enterVotes;
  final int exitFrames;
  final int missingFaceHoldFrames;

  /// Distraction means the gaze keeps moving away, not that the head rests at
  /// an angle. The baseline is captured once at camera start, so reading a
  /// book beside the screen holds the score above [exitThreshold] forever.
  /// Once the score stays inside a [settledGazeSpread] band for this long the
  /// user is focused on one spot, so the state releases and only re-arms after
  /// the head returns near baseline. A near-profile pose above
  /// [settledGazeMaxScore] is never desk work, so it stays flagged.
  final Duration settledGazeDuration;
  final double settledGazeSpread;
  final int settledGazeMinSamples;
  final double settledGazeMaxScore;
  final OneEuroFilter scoreFilter;

  final List<bool> _evidenceWindow = <bool>[];
  final List<_GazeSample> _gazeSamples = <_GazeSample>[];
  bool _isDistracted = false;
  bool _requiresRecenter = false;
  int _exitFrameCount = 0;
  int _missingFaceFrameCount = 0;

  HeadOffsetDetectionResult evaluate({
    required VisionResult result,
    required int previousDistractedFrameCount,
    DateTime? observedAt,
  }) {
    if (result.isHeadOffsetCalibrating) {
      reset();
      return const HeadOffsetDetectionResult(
        state: HeadOffsetState.unavailable,
        distractedFrameCount: 0,
      );
    }

    final rawScore = result.headOffsetScore;
    if (!result.hasFace || rawScore == null) {
      _missingFaceFrameCount++;
      // Only bridge a face-detection blip while the body is still visible;
      // if the user is fully gone, distraction must not be asserted.
      if (_isDistracted &&
          result.hasPose &&
          _missingFaceFrameCount <= missingFaceHoldFrames) {
        return HeadOffsetDetectionResult(
          state: HeadOffsetState.distracted,
          distractedFrameCount: previousDistractedFrameCount + 1,
        );
      }
      return const HeadOffsetDetectionResult(
        state: HeadOffsetState.unavailable,
        distractedFrameCount: 0,
      );
    }

    _missingFaceFrameCount = 0;
    final timestamp = observedAt ?? DateTime.now();
    final score = scoreFilter.filter(
      rawScore,
      timestampSeconds:
          timestamp.microsecondsSinceEpoch / Duration.microsecondsPerSecond,
    );

    if (_isDistracted) {
      if (score <= exitThreshold) {
        _exitFrameCount++;
      } else {
        _exitFrameCount = 0;
      }

      if (_exitFrameCount >= exitFrames) {
        _releaseDistraction();
        return const HeadOffsetDetectionResult(
          state: HeadOffsetState.normal,
          distractedFrameCount: 0,
        );
      }

      _recordGazeSample(timestamp, score);
      if (_hasSettledGaze(timestamp)) {
        _releaseDistraction();
        _requiresRecenter = true;
        return const HeadOffsetDetectionResult(
          state: HeadOffsetState.normal,
          distractedFrameCount: 0,
        );
      }

      return HeadOffsetDetectionResult(
        state: HeadOffsetState.distracted,
        distractedFrameCount: previousDistractedFrameCount + 1,
      );
    }

    if (_requiresRecenter) {
      // Released by settling, but the head has not come back yet. Staying at
      // the same angle must not immediately re-trigger the same reminder.
      if (score > exitThreshold) {
        return const HeadOffsetDetectionResult(
          state: HeadOffsetState.normal,
          distractedFrameCount: 0,
        );
      }
      _requiresRecenter = false;
    }

    // A high threshold plus 3-of-5 voting tolerates small page-to-page head
    // movements while still keeping a sustained, clearly off-axis gaze active.
    _addEvidence(score >= enterThreshold);
    final votes = _evidenceWindow.where((value) => value).length;
    if (votes >= enterVotes) {
      _isDistracted = true;
      _exitFrameCount = 0;
      _gazeSamples.clear();
      _recordGazeSample(timestamp, score);
      return HeadOffsetDetectionResult(
        state: HeadOffsetState.distracted,
        distractedFrameCount: votes,
      );
    }

    return HeadOffsetDetectionResult(
      state: HeadOffsetState.normal,
      distractedFrameCount: votes,
    );
  }

  void _addEvidence(bool value) {
    _evidenceWindow.add(value);
    if (_evidenceWindow.length > evidenceWindowSize) {
      _evidenceWindow.removeAt(0);
    }
  }

  void _releaseDistraction() {
    _isDistracted = false;
    _exitFrameCount = 0;
    _evidenceWindow.clear();
    _gazeSamples.clear();
  }

  void _recordGazeSample(DateTime timestamp, double score) {
    _gazeSamples.add(_GazeSample(timestamp: timestamp, score: score));
    // Keep exactly one sample older than the window so its span stays covered.
    while (_gazeSamples.length > 1 &&
        timestamp.difference(_gazeSamples[1].timestamp) >=
            settledGazeDuration) {
      _gazeSamples.removeAt(0);
    }
  }

  bool _hasSettledGaze(DateTime timestamp) {
    if (_gazeSamples.length < settledGazeMinSamples) return false;
    if (timestamp.difference(_gazeSamples.first.timestamp) <
        settledGazeDuration) {
      return false;
    }

    var lowest = _gazeSamples.first.score;
    var highest = _gazeSamples.first.score;
    for (final sample in _gazeSamples) {
      if (sample.score < lowest) lowest = sample.score;
      if (sample.score > highest) highest = sample.score;
    }
    if (highest > settledGazeMaxScore) return false;
    return highest - lowest <= settledGazeSpread;
  }

  void reset() {
    _evidenceWindow.clear();
    _gazeSamples.clear();
    _isDistracted = false;
    _requiresRecenter = false;
    _exitFrameCount = 0;
    _missingFaceFrameCount = 0;
    scoreFilter.reset();
  }
}

class _GazeSample {
  const _GazeSample({required this.timestamp, required this.score});

  final DateTime timestamp;
  final double score;
}
