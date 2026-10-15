import 'one_euro_filter.dart';
import 'vision_result.dart';

enum HeadOffsetState { unavailable, normal, distracted }

class HeadOffsetDetectionResult {
  const HeadOffsetDetectionResult({
    required this.state,
    required this.distractedFrameCount,
    this.scoreSum,
    this.scoreUsed,
    this.scoreImputed = false,
    this.scoreWindowSamples = 0,
    this.measuredHighSamples = 0,
  });

  final HeadOffsetState state;
  final int distractedFrameCount;
  final double? scoreSum;
  final double? scoreUsed;
  final bool scoreImputed;
  final int scoreWindowSamples;
  final int measuredHighSamples;
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
    this.useScoreSum = false,
    this.scoreSumMaximumGap = defaultScoreSumMaximumGap,
    OneEuroFilter? scoreFilter,
  }) : assert(scoreSumMaximumGap > Duration.zero),
       scoreFilter = scoreFilter ?? OneEuroFilter(minCutoff: 1.25, beta: 0.08);

  final double enterThreshold;
  final double exitThreshold;
  final int evidenceWindowSize;
  final int enterVotes;
  final int exitFrames;
  final int missingFaceHoldFrames;
  final bool useScoreSum;
  final Duration scoreSumMaximumGap;

  static const scoreSumWindowSize = 5;
  static const scoreSumEnterThreshold = 275.0;
  static const missingFaceFillScore = 50.0;
  static const scoreSumMinimumMeasuredHighSamples = 2;
  static const scoreSumMissingHold = Duration(seconds: 2);
  static const defaultScoreSumMaximumGap = Duration(milliseconds: 500);

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
  final List<_ScoreSample> _scoreWindow = [];
  DateTime? _lastSumObservationAt;
  DateTime? _lastMeasuredTurnAt;

  HeadOffsetDetectionResult evaluate({
    required VisionResult result,
    required int previousDistractedFrameCount,
    DateTime? observedAt,
    bool allowMissingFaceFill = false,
  }) {
    if (result.isHeadOffsetCalibrating) {
      reset();
      return const HeadOffsetDetectionResult(
        state: HeadOffsetState.unavailable,
        distractedFrameCount: 0,
      );
    }

    if (useScoreSum) {
      return _evaluateScoreSum(
        result: result,
        previousDistractedFrameCount: previousDistractedFrameCount,
        timestamp: observedAt ?? DateTime.now(),
        allowMissingFaceFill: allowMissingFaceFill,
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

  HeadOffsetDetectionResult _evaluateScoreSum({
    required VisionResult result,
    required int previousDistractedFrameCount,
    required DateTime timestamp,
    required bool allowMissingFaceFill,
  }) {
    if (_lastSumObservationAt != null) {
      final gap = timestamp.difference(_lastSumObservationAt!);
      if (gap <= Duration.zero) {
        throw ArgumentError('Score-sum timestamps must increase.');
      }
      if (gap > scoreSumMaximumGap) {
        reset();
      }
    }
    _lastSumObservationAt = timestamp;
    final rawScore = result.headOffsetScore;
    final measured = result.hasFace && rawScore != null && rawScore.isFinite;
    if (!measured) {
      _gazeSamples.clear();
      _exitFrameCount = 0;
      final canFill =
          !result.hasFace &&
          allowMissingFaceFill &&
          result.hasPose &&
          !_requiresRecenter &&
          _lastMeasuredTurnAt != null &&
          timestamp.difference(_lastMeasuredTurnAt!) <= scoreSumMissingHold;
      if (!canFill) {
        _releaseDistraction();
        _scoreWindow.clear();
        _lastMeasuredTurnAt = null;
        return _sumResult(HeadOffsetState.unavailable, 0);
      }
      _addScore(missingFaceFillScore, measured: false);
      if (!_isDistracted && _sumCanEnter) {
        _isDistracted = true;
      }
      return _sumResult(
        _isDistracted
            ? HeadOffsetState.distracted
            : HeadOffsetState.unavailable,
        _isDistracted ? previousDistractedFrameCount + 1 : 0,
        scoreUsed: missingFaceFillScore,
        imputed: true,
      );
    }

    // The native score is already smoothed. Preserve actual peak magnitudes.
    final score = rawScore.clamp(0.0, 100.0).toDouble();
    _addScore(score, measured: true);
    if (score >= enterThreshold &&
        _measuredHighSamples >= scoreSumMinimumMeasuredHighSamples) {
      _lastMeasuredTurnAt = timestamp;
    }
    if (_isDistracted) {
      _exitFrameCount = score <= exitThreshold ? _exitFrameCount + 1 : 0;
      if (_exitFrameCount >= exitFrames) {
        _releaseDistraction();
        _scoreWindow.clear();
        _lastMeasuredTurnAt = null;
        return _sumResult(HeadOffsetState.normal, 0, scoreUsed: score);
      }
      _recordGazeSample(timestamp, score);
      if (_hasSettledGaze(timestamp)) {
        _releaseDistraction();
        _requiresRecenter = true;
        _scoreWindow.clear();
        _lastMeasuredTurnAt = null;
        return _sumResult(HeadOffsetState.normal, 0, scoreUsed: score);
      }
      return _sumResult(
        HeadOffsetState.distracted,
        previousDistractedFrameCount + 1,
        scoreUsed: score,
      );
    }
    if (_requiresRecenter) {
      if (score > exitThreshold) {
        return _sumResult(HeadOffsetState.normal, 0, scoreUsed: score);
      }
      _requiresRecenter = false;
      _scoreWindow.clear();
      _lastMeasuredTurnAt = null;
      _addScore(score, measured: true);
    }
    if (_sumCanEnter) {
      _isDistracted = true;
      _exitFrameCount = 0;
      _gazeSamples.clear();
      _recordGazeSample(timestamp, score);
      return _sumResult(HeadOffsetState.distracted, 1, scoreUsed: score);
    }
    return _sumResult(HeadOffsetState.normal, 0, scoreUsed: score);
  }

  double get _scoreSum =>
      _scoreWindow.fold(0.0, (sum, sample) => sum + sample.score);
  int get _measuredHighSamples => _scoreWindow
      .where((sample) => sample.measured && sample.score >= enterThreshold)
      .length;
  bool get _sumCanEnter =>
      _scoreWindow.length == scoreSumWindowSize &&
      _scoreSum >= scoreSumEnterThreshold &&
      _measuredHighSamples >= scoreSumMinimumMeasuredHighSamples;

  void _addScore(double score, {required bool measured}) {
    _scoreWindow.add(_ScoreSample(score, measured));
    if (_scoreWindow.length > scoreSumWindowSize) {
      _scoreWindow.removeAt(0);
    }
  }

  HeadOffsetDetectionResult _sumResult(
    HeadOffsetState state,
    int count, {
    double? scoreUsed,
    bool imputed = false,
  }) => HeadOffsetDetectionResult(
    state: state,
    distractedFrameCount: count,
    scoreSum: _scoreSum,
    scoreUsed: scoreUsed,
    scoreImputed: imputed,
    scoreWindowSamples: _scoreWindow.length,
    measuredHighSamples: _measuredHighSamples,
  );

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
    _scoreWindow.clear();
    _lastSumObservationAt = null;
    _lastMeasuredTurnAt = null;
    scoreFilter.reset();
  }
}

class _ScoreSample {
  const _ScoreSample(this.score, this.measured);
  final double score;
  final bool measured;
}

class _GazeSample {
  const _GazeSample({required this.timestamp, required this.score});

  final DateTime timestamp;
  final double score;
}
