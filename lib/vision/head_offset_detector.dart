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
    OneEuroFilter? scoreFilter,
  }) : scoreFilter = scoreFilter ?? OneEuroFilter(minCutoff: 1.25, beta: 0.08);

  final double enterThreshold;
  final double exitThreshold;
  final int evidenceWindowSize;
  final int enterVotes;
  final int exitFrames;
  final int missingFaceHoldFrames;
  final OneEuroFilter scoreFilter;

  final List<bool> _evidenceWindow = <bool>[];
  bool _isDistracted = false;
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
      if (_isDistracted && _missingFaceFrameCount <= missingFaceHoldFrames) {
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

    _addEvidence(score >= enterThreshold);
    final votes = _evidenceWindow.where((value) => value).length;
    if (votes >= enterVotes) {
      _isDistracted = true;
      _exitFrameCount = 0;
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

  void reset() {
    _evidenceWindow.clear();
    _isDistracted = false;
    _exitFrameCount = 0;
    _missingFaceFrameCount = 0;
    scoreFilter.reset();
  }
}
