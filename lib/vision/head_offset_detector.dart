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
    this.stableGazeDuration = const Duration(seconds: 8),
    this.stableGazeTolerance = 12,
    OneEuroFilter? scoreFilter,
  }) : scoreFilter = scoreFilter ?? OneEuroFilter(minCutoff: 1.25, beta: 0.08);

  final double enterThreshold;
  final double exitThreshold;
  final int evidenceWindowSize;
  final int enterVotes;
  final int exitFrames;
  final int missingFaceHoldFrames;

  /// Distraction means rapid gaze changes, not a fixed head direction. If the
  /// offset score stays within [stableGazeTolerance] for this long, the user
  /// is focusing on something (book, second screen) and the distracted state
  /// releases until the head returns near baseline to re-arm.
  final Duration stableGazeDuration;
  final double stableGazeTolerance;
  final OneEuroFilter scoreFilter;

  final List<bool> _evidenceWindow = <bool>[];
  bool _isDistracted = false;
  int _exitFrameCount = 0;
  int _missingFaceFrameCount = 0;
  DateTime? _stableGazeStartAt;
  double? _stableGazeAnchorScore;
  bool _requiresRearm = false;

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
        _isDistracted = false;
        _exitFrameCount = 0;
        _evidenceWindow.clear();
        _clearStableGazeTracking();
        return const HeadOffsetDetectionResult(
          state: HeadOffsetState.normal,
          distractedFrameCount: 0,
        );
      }

      final anchor = _stableGazeAnchorScore;
      if (anchor == null || (score - anchor).abs() > stableGazeTolerance) {
        _stableGazeAnchorScore = score;
        _stableGazeStartAt = timestamp;
      } else if (timestamp.difference(_stableGazeStartAt ?? timestamp) >=
          stableGazeDuration) {
        // The gaze has settled on one spot: that is focus, not distraction.
        // Release, and stay released until the head returns near baseline.
        _isDistracted = false;
        _exitFrameCount = 0;
        _evidenceWindow.clear();
        _clearStableGazeTracking();
        _requiresRearm = true;
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

    if (_requiresRearm) {
      if (score <= exitThreshold) {
        _requiresRearm = false;
      } else {
        return const HeadOffsetDetectionResult(
          state: HeadOffsetState.normal,
          distractedFrameCount: 0,
        );
      }
    }

    _addEvidence(score >= enterThreshold);
    final votes = _evidenceWindow.where((value) => value).length;
    if (votes >= enterVotes) {
      _isDistracted = true;
      _exitFrameCount = 0;
      _stableGazeAnchorScore = score;
      _stableGazeStartAt = timestamp;
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

  void _clearStableGazeTracking() {
    _stableGazeAnchorScore = null;
    _stableGazeStartAt = null;
  }

  void reset() {
    _evidenceWindow.clear();
    _isDistracted = false;
    _exitFrameCount = 0;
    _missingFaceFrameCount = 0;
    _clearStableGazeTracking();
    _requiresRearm = false;
    scoreFilter.reset();
  }
}
