import 'dart:math' as math;

import 'one_euro_filter.dart';
import 'vision_result.dart';

enum PostureDownState { unavailable, normal, down }

class PostureDownDetectionResult {
  const PostureDownDetectionResult({
    required this.state,
    required this.score,
    required this.downFrameCount,
    this.headLowScore,
    this.shoulderDropScore,
    this.noseDropScore,
    this.visibilityScore,
    this.sideProneScore,
    this.shoulderShrinkScore,
    this.headShoulderRatio,
    this.shoulderCenterYRatio,
    this.noseYRatio,
    this.isCalibrating = false,
  });

  final PostureDownState state;
  final double? score;
  final int downFrameCount;
  final double? headLowScore;
  final double? shoulderDropScore;
  final double? noseDropScore;
  final double? visibilityScore;
  final double? sideProneScore;
  final double? shoulderShrinkScore;
  final double? headShoulderRatio;
  final double? shoulderCenterYRatio;
  final double? noseYRatio;
  final bool isCalibrating;
}

class PostureDownDetector {
  PostureDownDetector({
    this.downScoreThreshold = 35,
    this.evidenceWindowSize = 3,
    this.confirmationVotes = 2,
    this.recoveryFrames = 2,
    this.baselineFrames = 5,
    this.missingPoseHoldFrames = 8,
    this.confirmedMissingPoseHoldFrames = 24,
    this.downwardMotionWindowFrames = 8,
    this.downwardMotionMinDrop = 0.02,
    this.motionHistoryFrames = 5,
    this.upwardMotionVetoFrames = 10,
    this.motionReliableShoulderVisibility = 0.6,
    this.shoulderDropRatioForMaxScore = 0.06,
    this.noseDropRatioForMaxScore = 0.06,
    this.shoulderShrinkRatioForMaxScore = 0.22,
    OneEuroFilter? headShoulderFilter,
    OneEuroFilter? shoulderCenterFilter,
    OneEuroFilter? noseYFilter,
    OneEuroFilter? shoulderWidthFilter,
  }) : headShoulderFilter =
           headShoulderFilter ?? OneEuroFilter(minCutoff: 1.2, beta: 0.05),
       shoulderCenterFilter =
           shoulderCenterFilter ?? OneEuroFilter(minCutoff: 1.2, beta: 0.05),
       noseYFilter = noseYFilter ?? OneEuroFilter(minCutoff: 1.2, beta: 0.05),
       shoulderWidthFilter =
           shoulderWidthFilter ?? OneEuroFilter(minCutoff: 1.2, beta: 0.05);

  final double downScoreThreshold;
  final int evidenceWindowSize;
  final int confirmationVotes;
  final int recoveryFrames;
  final int baselineFrames;
  final int missingPoseHoldFrames;
  final int confirmedMissingPoseHoldFrames;
  final int downwardMotionWindowFrames;
  final double downwardMotionMinDrop;
  final int motionHistoryFrames;
  final int upwardMotionVetoFrames;
  final double motionReliableShoulderVisibility;
  final double shoulderDropRatioForMaxScore;
  final double noseDropRatioForMaxScore;
  final double shoulderShrinkRatioForMaxScore;
  final OneEuroFilter headShoulderFilter;
  final OneEuroFilter shoulderCenterFilter;
  final OneEuroFilter noseYFilter;
  final OneEuroFilter shoulderWidthFilter;

  final List<double> _baselineHeadShoulderRatioSamples = <double>[];
  final List<double> _baselineShoulderCenterYRatioSamples = <double>[];
  final List<double> _baselineNoseYRatioSamples = <double>[];
  final List<double> _baselineShoulderWidthRatioSamples = <double>[];
  double? _baselineHeadShoulderRatio;
  double? _baselineShoulderCenterYRatio;
  double? _baselineNoseYRatio;
  double? _baselineShoulderWidthRatio;
  _PostureScore? _lastScore;
  _PostureScore? _lastDownScore;
  final List<bool> _downEvidenceWindow = <bool>[];
  bool _isDownConfirmed = false;
  int _missingPoseFrameCount = 0;
  int _recoveryFrameCount = 0;
  final List<double> _noseYHistory = <double>[];
  final List<double> _shoulderYHistory = <double>[];
  int _downwardMotionFrames = 0;
  int _upwardVetoFramesLeft = 0;
  int _consecutiveDownFrames = 0;
  int _unreliableMotionFrames = 0;

  PostureDownDetectionResult evaluate({
    required VisionResult result,
    required bool shouldUpdate,
    DateTime? observedAt,
  }) {
    if (!shouldUpdate) {
      final score = _lastScore;
      if (score == null) {
        return const PostureDownDetectionResult(
          state: PostureDownState.unavailable,
          score: null,
          downFrameCount: 0,
        );
      }

      return _holdScore(score: score);
    }

    final score = _calculateScore(
      result,
      shouldUpdate: shouldUpdate,
      observedAt: observedAt,
    );
    if (score == null) {
      _missingPoseFrameCount++;
      final lastScore = _lastScore;

      if (lastScore != null &&
          _missingPoseFrameCount <= missingPoseHoldFrames) {
        return _holdScore(score: _lastDownScore ?? lastScore);
      }

      if (_isDownConfirmed && _lastDownScore != null) {
        if (_missingPoseFrameCount <= confirmedMissingPoseHoldFrames) {
          return _holdScore(score: _lastDownScore!);
        }
        // Pose has been gone far too long to keep asserting a prone posture;
        // release the confirmed state instead of holding it indefinitely.
        _clearConfirmedState();
        _lastScore = null;
      }
      return const PostureDownDetectionResult(
        state: PostureDownState.unavailable,
        score: null,
        downFrameCount: 0,
      );
    }
    _missingPoseFrameCount = 0;

    return _evaluateScore(score: score);
  }

  PostureDownDetectionResult _holdScore({required _PostureScore score}) {
    final displayScore = _isDownConfirmed
        ? score
        : _withTotal(score, math.min(score.total, downScoreThreshold - 1));

    return _buildResultFromScore(
      score: displayScore,
      downFrameCount: _positiveEvidenceVotes,
      state: _isDownConfirmed ? PostureDownState.down : PostureDownState.normal,
    );
  }

  PostureDownDetectionResult _evaluateScore({required _PostureScore score}) {
    _lastScore = score;
    _updateVerticalMotion(score);
    if (score.isCalibrating) {
      _downEvidenceWindow.clear();
      _recoveryFrameCount = 0;
      return _buildResultFromScore(
        score: score,
        downFrameCount: 0,
        state: PostureDownState.normal,
      );
    }

    // Lying down always involves the head/shoulders travelling downward
    // first; without recent downward motion (e.g. walking out of frame
    // sideways or standing up) prone evidence must not accumulate votes.
    final isDownEvidence =
        _downwardMotionFrames > 0 && _isPostureDownEvidence(score);
    _addDownEvidence(isDownEvidence);

    if (_isDownConfirmed) {
      if (_isClearlyRecovered(score)) {
        _recoveryFrameCount++;
      } else {
        _recoveryFrameCount = 0;
      }

      if (_recoveryFrameCount < recoveryFrames) {
        final heldScore = _lastDownScore ?? score;
        return _buildResultFromScore(
          score: heldScore,
          downFrameCount: _positiveEvidenceVotes,
          state: PostureDownState.down,
        );
      }

      _clearConfirmedState();
      _lastScore = score;
      return _buildResultFromScore(
        score: score,
        downFrameCount: 0,
        state: PostureDownState.normal,
      );
    }

    if (_positiveEvidenceVotes >= confirmationVotes) {
      _isDownConfirmed = true;
      _lastDownScore = score;
      _recoveryFrameCount = 0;
      return _buildResultFromScore(
        score: score,
        downFrameCount: _positiveEvidenceVotes,
        state: PostureDownState.down,
      );
    }

    final displayScore = isDownEvidence
        ? _withTotal(score, math.min(score.total, downScoreThreshold - 1))
        : score;
    return _buildResultFromScore(
      score: displayScore,
      downFrameCount: _positiveEvidenceVotes,
      state: PostureDownState.normal,
    );
  }

  void _updateVerticalMotion(_PostureScore score) {
    if (!score.isMotionReliable) {
      // Landmarks are hallucinated (face gone and shoulders barely visible):
      // these frames may spend an already-armed window on votes, but must
      // never arm or extend it. Only pre-loss, trustworthy frames decide
      // whether a descent actually happened.
      _consecutiveDownFrames = 0;
      if (_upwardVetoFramesLeft > 0) {
        _upwardVetoFramesLeft--;
      }
      if (_downwardMotionFrames > 0) {
        _downwardMotionFrames--;
      }
      _unreliableMotionFrames++;
      if (_unreliableMotionFrames > motionHistoryFrames) {
        _noseYHistory.clear();
        _shoulderYHistory.clear();
      }
      return;
    }
    _unreliableMotionFrames = 0;

    if (_noseYHistory.isNotEmpty) {
      final noseDelta = score.noseYRatio - _noseYHistory.first;
      final shoulderDelta = score.shoulderCenterYRatio - _shoulderYHistory.first;
      final movingUp =
          noseDelta <= -downwardMotionMinDrop ||
          shoulderDelta <= -downwardMotionMinDrop;
      final movingDown =
          noseDelta >= downwardMotionMinDrop ||
          shoulderDelta >= downwardMotionMinDrop;

      if (movingUp) {
        // Rising head/shoulders means standing up or straightening; the
        // hallucinated landmarks that follow a frame exit jump around and
        // must not arm the prone vote window.
        _consecutiveDownFrames = 0;
        _upwardVetoFramesLeft = upwardMotionVetoFrames;
        _downwardMotionFrames = 0;
      } else if (movingDown) {
        _consecutiveDownFrames++;
        // A real slump descends monotonically, so two consecutive downward
        // frames override the veto; garbage landmarks flip up and down.
        if (_upwardVetoFramesLeft == 0 || _consecutiveDownFrames >= 2) {
          _upwardVetoFramesLeft = 0;
          _downwardMotionFrames = downwardMotionWindowFrames;
        } else {
          _upwardVetoFramesLeft--;
        }
      } else {
        _consecutiveDownFrames = 0;
        if (_upwardVetoFramesLeft > 0) {
          _upwardVetoFramesLeft--;
        }
        if (_downwardMotionFrames > 0) {
          _downwardMotionFrames--;
        }
      }
    }
    _noseYHistory.add(score.noseYRatio);
    _shoulderYHistory.add(score.shoulderCenterYRatio);
    if (_noseYHistory.length > motionHistoryFrames) {
      _noseYHistory.removeAt(0);
      _shoulderYHistory.removeAt(0);
    }
  }

  int get _positiveEvidenceVotes =>
      _downEvidenceWindow.where((value) => value).length;

  void _addDownEvidence(bool value) {
    _downEvidenceWindow.add(value);
    if (_downEvidenceWindow.length > evidenceWindowSize) {
      _downEvidenceWindow.removeAt(0);
    }
  }

  bool _isPostureDownEvidence(_PostureScore score) {
    final bodyCollapsed =
        score.shoulderDrop >= 24 || score.shoulderShrink >= 45;
    final headCollapsed = score.headLow >= 55 || score.noseDrop >= 70;
    final proneContext = !score.hasFace || score.sideProne >= 65;
    return score.total >= downScoreThreshold &&
        bodyCollapsed &&
        (headCollapsed || proneContext);
  }

  _PostureScore? _calculateScore(
    VisionResult result, {
    bool shouldUpdate = true,
    DateTime? observedAt,
  }) {
    final shoulderCenterY = result.shoulderCenterY;
    final shoulderWidth = result.shoulderWidth;
    final imageWidth = result.imageWidth;
    final imageHeight = result.imageHeight;
    final noseY = result.poseNoseY;
    if (!result.hasPose ||
        shoulderCenterY == null ||
        imageWidth == null ||
        imageWidth <= 0 ||
        imageHeight == null ||
        imageHeight <= 0 ||
        shoulderWidth == null ||
        shoulderWidth <= 0 ||
        noseY == null) {
      return null;
    }

    final timestamp = observedAt ?? DateTime.now();
    final timestampSeconds =
        timestamp.microsecondsSinceEpoch / Duration.microsecondsPerSecond;
    final headShoulderRatio = headShoulderFilter.filter(
      (shoulderCenterY - noseY) / shoulderWidth,
      timestampSeconds: timestampSeconds,
    );
    final shoulderWidthRatio = shoulderWidthFilter.filter(
      shoulderWidth / imageWidth,
      timestampSeconds: timestampSeconds,
    );
    final shoulderCenterYRatio = shoulderCenterFilter.filter(
      shoulderCenterY / imageHeight,
      timestampSeconds: timestampSeconds,
    );
    final noseYRatio = noseYFilter.filter(
      noseY / imageHeight,
      timestampSeconds: timestampSeconds,
    );

    final motionShoulderVisibility = _average([
      result.leftShoulderVisibility,
      result.rightShoulderVisibility,
    ]);
    final isMotionReliable =
        result.hasFace ||
        (motionShoulderVisibility != null &&
            motionShoulderVisibility >= motionReliableShoulderVisibility);

    if (_baselineHeadShoulderRatio == null) {
      if (shouldUpdate && _canUseForBaseline(result)) {
        _recordBaseline(
          headShoulderRatio: headShoulderRatio,
          shoulderWidthRatio: shoulderWidthRatio,
          shoulderCenterYRatio: shoulderCenterYRatio,
          noseYRatio: noseYRatio,
        );
      }
      return _PostureScore(
        total: 0,
        headLow: 0,
        shoulderDrop: 0,
        noseDrop: 0,
        visibility: 0,
        sideProne: 0,
        shoulderShrink: 0,
        headShoulderRatio: headShoulderRatio,
        shoulderCenterYRatio: shoulderCenterYRatio,
        noseYRatio: noseYRatio,
        hasFace: result.hasFace,
        isMotionReliable: isMotionReliable,
        isCalibrating: true,
      );
    }

    final headLowScore = _headLowScore(headShoulderRatio: headShoulderRatio);
    final shoulderDropScore = _dropScore(
      current: shoulderCenterYRatio,
      baseline: _baselineShoulderCenterYRatio,
      maxDrop: shoulderDropRatioForMaxScore,
    );
    final noseDropScore = _dropScore(
      current: noseYRatio,
      baseline: _baselineNoseYRatio,
      maxDrop: noseDropRatioForMaxScore,
    );
    final shoulderShrinkScore = _shoulderShrinkScore(
      shoulderWidthRatio: shoulderWidthRatio,
    );
    final visibilityScore = _visibilityLossScore(result);
    final sideProneScore = _sideProneScore(
      result: result,
      headLowScore: headLowScore,
      shoulderShrinkScore: shoulderShrinkScore,
      shoulderDropScore: shoulderDropScore,
      noseDropScore: noseDropScore,
    );

    final headDropScore = math.max(headLowScore, noseDropScore);
    final hasBodyCollapseEvidence =
        shoulderShrinkScore >= 45 ||
        sideProneScore >= 55 ||
        !result.hasFace && shoulderDropScore >= 20;
    final gatedHeadDropScore = hasBodyCollapseEvidence ? headDropScore : 0.0;

    final gatedShoulderDropScore =
        result.hasFace && shoulderShrinkScore < 45 && sideProneScore < 55
        ? math.min(shoulderDropScore, downScoreThreshold - 1)
        : shoulderDropScore;
    final hasBodyCollapseEvidenceForProne =
        shoulderShrinkScore >= 45 || shoulderDropScore >= 24;
    final gatedSideProneScore = hasBodyCollapseEvidenceForProne
        ? sideProneScore
        : 0.0;

    final rawTotal = [
      gatedShoulderDropScore,
      shoulderShrinkScore,
      gatedHeadDropScore,
      visibilityScore,
      gatedSideProneScore,
    ].reduce(math.max);
    final bodyCollapseScore = math.max(shoulderDropScore, shoulderShrinkScore);
    final faceVisibleWithoutBodyCollapse =
        result.hasFace && bodyCollapseScore < 45;
    final total = faceVisibleWithoutBodyCollapse
        ? math.min(rawTotal, downScoreThreshold - 1)
        : rawTotal;

    return _PostureScore(
      total: total,
      headLow: headLowScore,
      shoulderDrop: shoulderDropScore,
      noseDrop: noseDropScore,
      visibility: visibilityScore,
      sideProne: sideProneScore,
      shoulderShrink: shoulderShrinkScore,
      headShoulderRatio: headShoulderRatio,
      shoulderCenterYRatio: shoulderCenterYRatio,
      noseYRatio: noseYRatio,
      hasFace: result.hasFace,
      isMotionReliable: isMotionReliable,
    );
  }

  bool _canUseForBaseline(VisionResult result) {
    if (!result.hasFace) return false;
    final leftVisibility = result.leftShoulderVisibility;
    final rightVisibility = result.rightShoulderVisibility;
    if (leftVisibility != null && leftVisibility < 0.5) return false;
    if (rightVisibility != null && rightVisibility < 0.5) return false;
    final pitch = result.headPitch;
    if (pitch != null && pitch.abs() > 25) return false;
    return true;
  }

  double _headLowScore({required double headShoulderRatio}) {
    final baseline = _baselineHeadShoulderRatio;
    if (baseline == null || baseline <= 0) return 0;
    final meaningfulDrop = math.max(0.10, baseline * 0.65);
    return ((baseline - headShoulderRatio) / meaningfulDrop * 100)
        .clamp(0, 100)
        .toDouble();
  }

  double _dropScore({
    required double current,
    required double? baseline,
    required double maxDrop,
  }) {
    if (baseline == null || maxDrop <= 0) return 0;
    return ((current - baseline) / maxDrop * 100).clamp(0, 100).toDouble();
  }

  void _recordBaseline({
    required double headShoulderRatio,
    required double shoulderWidthRatio,
    required double shoulderCenterYRatio,
    required double noseYRatio,
  }) {
    _baselineHeadShoulderRatioSamples.add(headShoulderRatio);
    _baselineShoulderWidthRatioSamples.add(shoulderWidthRatio);
    _baselineShoulderCenterYRatioSamples.add(shoulderCenterYRatio);
    _baselineNoseYRatioSamples.add(noseYRatio);

    if (_baselineHeadShoulderRatioSamples.length >= baselineFrames) {
      _baselineHeadShoulderRatio = _median(_baselineHeadShoulderRatioSamples);
      _baselineShoulderCenterYRatio = _median(
        _baselineShoulderCenterYRatioSamples,
      );
      _baselineNoseYRatio = _median(_baselineNoseYRatioSamples);
      _baselineShoulderWidthRatio = _median(_baselineShoulderWidthRatioSamples);
    }
  }

  void reset() {
    _baselineHeadShoulderRatioSamples.clear();
    _baselineShoulderWidthRatioSamples.clear();
    _baselineShoulderCenterYRatioSamples.clear();
    _baselineNoseYRatioSamples.clear();
    _baselineHeadShoulderRatio = null;
    _baselineShoulderWidthRatio = null;
    _baselineShoulderCenterYRatio = null;
    _baselineNoseYRatio = null;
    _lastScore = null;
    _lastDownScore = null;
    _downEvidenceWindow.clear();
    _isDownConfirmed = false;
    _missingPoseFrameCount = 0;
    _recoveryFrameCount = 0;
    _noseYHistory.clear();
    _shoulderYHistory.clear();
    _downwardMotionFrames = 0;
    _upwardVetoFramesLeft = 0;
    _consecutiveDownFrames = 0;
    _unreliableMotionFrames = 0;
    headShoulderFilter.reset();
    shoulderCenterFilter.reset();
    noseYFilter.reset();
    shoulderWidthFilter.reset();
  }

  void _clearConfirmedState() {
    _downEvidenceWindow.clear();
    _isDownConfirmed = false;
    _lastDownScore = null;
    _recoveryFrameCount = 0;
  }

  double _visibilityLossScore(VisionResult result) {
    final shoulderVisibility = _average([
      result.leftShoulderVisibility,
      result.rightShoulderVisibility,
    ]);
    if (shoulderVisibility == null || shoulderVisibility < 0.55) {
      return 0;
    }

    final headVisibility = _average([
      result.poseNoseVisibility,
      result.poseLeftEyeVisibility,
      result.poseRightEyeVisibility,
      result.poseLeftEarVisibility,
      result.poseRightEarVisibility,
    ]);
    if (headVisibility == null) return 0;

    return ((1.0 - headVisibility) * 100).clamp(0, 100).toDouble();
  }

  double _sideProneScore({
    required VisionResult result,
    required double headLowScore,
    required double shoulderShrinkScore,
    required double shoulderDropScore,
    required double noseDropScore,
  }) {
    final shoulderVisibility = _average([
      result.leftShoulderVisibility,
      result.rightShoulderVisibility,
    ]);
    if (shoulderVisibility == null || shoulderVisibility < 0.35) {
      return 0;
    }

    final visibleShoulderCount = [
      result.leftShoulderVisibility,
      result.rightShoulderVisibility,
    ].whereType<double>().where((visibility) => visibility >= 0.45).length;

    final headVisibility = _average([
      result.poseNoseVisibility,
      result.poseLeftEyeVisibility,
      result.poseRightEyeVisibility,
      result.poseLeftEarVisibility,
      result.poseRightEarVisibility,
    ]);

    final headDropEvidence = math.max(headLowScore, noseDropScore);
    final faceMissingShoulderDropScore = _faceMissingShoulderDropScore(
      hasFace: result.hasFace,
      shoulderDropScore: shoulderDropScore,
      shoulderVisibility: shoulderVisibility,
      visibleShoulderCount: visibleShoulderCount,
    );
    if (faceMissingShoulderDropScore > 0) {
      return faceMissingShoulderDropScore;
    }

    if (headLowScore < 25 && noseDropScore < 55) {
      return 0;
    }
    if (headDropEvidence < 35) return 0;
    if (result.hasFace &&
        (headLowScore < 45 ||
            (shoulderShrinkScore < 35 && shoulderDropScore < 50))) {
      return 0;
    }
    if (!result.hasFace &&
        headLowScore < 55 &&
        shoulderDropScore < 25 &&
        shoulderShrinkScore < 45) {
      return 0;
    }

    final faceLossEvidence = result.hasFace ? 0.0 : 28.0;
    final headVisibilityLoss = headVisibility == null
        ? 20.0
        : ((0.55 - headVisibility) / 0.55 * 45).clamp(0, 45).toDouble();

    var score = headDropEvidence * 0.72 + faceLossEvidence + headVisibilityLoss;
    if (visibleShoulderCount <= 1 && !result.hasFace) {
      score = math.max(score, 58 + headDropEvidence * 0.35);
    }
    if (shoulderShrinkScore >= 45 && !result.hasFace) {
      score = math.max(score, 62 + shoulderShrinkScore * 0.35);
    }

    return score.clamp(0, 100).toDouble();
  }

  double _faceMissingShoulderDropScore({
    required bool hasFace,
    required double shoulderDropScore,
    required double shoulderVisibility,
    required int visibleShoulderCount,
  }) {
    if (hasFace || shoulderDropScore < 24) return 0;

    final visibilityBonus = ((shoulderVisibility - 0.35) / 0.45 * 12)
        .clamp(0, 12)
        .toDouble();
    final singleShoulderBonus = visibleShoulderCount <= 1 ? 8.0 : 0.0;
    return (52 +
            shoulderDropScore * 1.25 +
            visibilityBonus +
            singleShoulderBonus)
        .clamp(0, 100)
        .toDouble();
  }

  double _shoulderShrinkScore({required double shoulderWidthRatio}) {
    final baseline = _baselineShoulderWidthRatio;
    if (baseline == null || shoulderShrinkRatioForMaxScore <= 0) return 0;
    return ((baseline - shoulderWidthRatio) /
            shoulderShrinkRatioForMaxScore *
            100)
        .clamp(0, 100)
        .toDouble();
  }

  double? _average(List<double?> values) {
    final validValues = values.whereType<double>().toList();
    if (validValues.isEmpty) return null;
    return validValues.reduce((sum, value) => sum + value) / validValues.length;
  }

  double _median(List<double> values) {
    final sorted = List<double>.from(values)..sort();
    final middle = sorted.length ~/ 2;
    if (sorted.length.isEven) {
      return (sorted[middle - 1] + sorted[middle]) / 2;
    }
    return sorted[middle];
  }

  _PostureScore _withTotal(_PostureScore score, double total) {
    return _PostureScore(
      total: total,
      headLow: score.headLow,
      shoulderDrop: score.shoulderDrop,
      noseDrop: score.noseDrop,
      visibility: score.visibility,
      sideProne: score.sideProne,
      shoulderShrink: score.shoulderShrink,
      headShoulderRatio: score.headShoulderRatio,
      shoulderCenterYRatio: score.shoulderCenterYRatio,
      noseYRatio: score.noseYRatio,
      hasFace: score.hasFace,
      isMotionReliable: score.isMotionReliable,
      isCalibrating: score.isCalibrating,
    );
  }

  bool _isClearlyRecovered(_PostureScore score) {
    final faceVisibleStableRecovery =
        score.hasFace &&
        score.sideProne < 45 &&
        score.shoulderShrink < 45 &&
        score.headLow < 45 &&
        score.noseDrop < 60;

    // Body is clearly back at baseline even though the face has not been
    // re-acquired yet; require stricter thresholds plus good head landmark
    // visibility so a true prone pose cannot pass.
    final bodyOnlyStableRecovery =
        !score.hasFace &&
        score.sideProne < 40 &&
        score.shoulderDrop < 25 &&
        score.shoulderShrink < 35 &&
        score.headLow < 50 &&
        score.noseDrop < 55 &&
        score.visibility < 40;

    return faceVisibleStableRecovery ||
        bodyOnlyStableRecovery ||
        score.hasFace &&
            score.total < downScoreThreshold &&
            score.sideProne < 55 &&
            score.shoulderDrop < 50 &&
            score.shoulderShrink < 45;
  }

  PostureDownDetectionResult _buildResultFromScore({
    required _PostureScore score,
    required int downFrameCount,
    required PostureDownState state,
  }) {
    return PostureDownDetectionResult(
      state: state,
      score: score.total,
      downFrameCount: downFrameCount,
      headLowScore: score.headLow,
      shoulderDropScore: score.shoulderDrop,
      noseDropScore: score.noseDrop,
      visibilityScore: score.visibility,
      sideProneScore: score.sideProne,
      shoulderShrinkScore: score.shoulderShrink,
      headShoulderRatio: score.headShoulderRatio,
      shoulderCenterYRatio: score.shoulderCenterYRatio,
      noseYRatio: score.noseYRatio,
      isCalibrating: score.isCalibrating,
    );
  }
}

class _PostureScore {
  const _PostureScore({
    required this.total,
    required this.headLow,
    required this.shoulderDrop,
    required this.noseDrop,
    required this.visibility,
    required this.sideProne,
    required this.shoulderShrink,
    required this.headShoulderRatio,
    required this.shoulderCenterYRatio,
    required this.noseYRatio,
    required this.hasFace,
    this.isMotionReliable = true,
    this.isCalibrating = false,
  });

  final double total;
  final double headLow;
  final double shoulderDrop;
  final double noseDrop;
  final double visibility;
  final double sideProne;
  final double shoulderShrink;
  final double headShoulderRatio;
  final double shoulderCenterYRatio;
  final double noseYRatio;
  final bool hasFace;
  final bool isMotionReliable;
  final bool isCalibrating;
}
