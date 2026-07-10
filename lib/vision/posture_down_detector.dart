import 'dart:math' as math;

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
    this.strongDownScoreThreshold = 70,
    this.downFrames = 2,
    this.recoveryFrames = 3,
    this.baselineFrames = 3,
    this.missingPoseHoldFrames = 8,
    this.shoulderDropRatioForMaxScore = 0.06,
    this.noseDropRatioForMaxScore = 0.06,
    this.shoulderShrinkRatioForMaxScore = 0.22,
  });

  final double downScoreThreshold;
  final double strongDownScoreThreshold;
  final int downFrames;
  final int recoveryFrames;
  final int baselineFrames;
  final int missingPoseHoldFrames;
  final double shoulderDropRatioForMaxScore;
  final double noseDropRatioForMaxScore;
  final double shoulderShrinkRatioForMaxScore;

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
  int _missingPoseFrameCount = 0;
  int _recoveryFrameCount = 0;

  PostureDownDetectionResult evaluate({
    required VisionResult result,
    required int previousDownFrameCount,
    required bool shouldUpdate,
  }) {
    if (!shouldUpdate) {
      if (result.hasFace && !result.hasPose) {
        _clearDownHold();
        return const PostureDownDetectionResult(
          state: PostureDownState.unavailable,
          score: null,
          downFrameCount: 0,
        );
      }

      final score = _lastScore;
      if (score == null) {
        return const PostureDownDetectionResult(
          state: PostureDownState.unavailable,
          score: null,
          downFrameCount: 0,
        );
      }

      return _holdScore(
        score: score,
        previousDownFrameCount: previousDownFrameCount,
      );
    }

    final score = _calculateScore(result, shouldUpdate: shouldUpdate);
    if (score == null) {
      if (result.hasFace) {
        _clearDownHold();
        return const PostureDownDetectionResult(
          state: PostureDownState.unavailable,
          score: null,
          downFrameCount: 0,
        );
      }

      _missingPoseFrameCount++;
      final lastScore = _lastScore;
      if (lastScore != null &&
          _missingPoseFrameCount <= missingPoseHoldFrames) {
        if (previousDownFrameCount >= downFrames) {
          final heldScore = _lastDownScore ?? lastScore;
          return _buildResultFromScore(
            score: heldScore,
            downFrameCount: previousDownFrameCount + 1,
            state: PostureDownState.down,
          );
        }

        return _holdScore(
          score: lastScore,
          previousDownFrameCount: previousDownFrameCount,
        );
      }

      return const PostureDownDetectionResult(
        state: PostureDownState.unavailable,
        score: null,
        downFrameCount: 0,
      );
    }
    _missingPoseFrameCount = 0;

    return _evaluateScore(
      score: score,
      previousDownFrameCount: previousDownFrameCount,
    );
  }

  PostureDownDetectionResult _holdScore({
    required _PostureScore score,
    required int previousDownFrameCount,
  }) {
    final canConfirmFromHeldFrame =
        previousDownFrameCount > 0 && _isStrongProneEvidence(score);
    final downFrameCount = canConfirmFromHeldFrame
        ? math.min(previousDownFrameCount + 1, downFrames)
        : previousDownFrameCount;
    final isConfirmedDown = downFrameCount >= downFrames;
    if (isConfirmedDown) {
      _lastDownScore = score;
    }

    final displayScore = isConfirmedDown
        ? score
        : _withTotal(score, math.min(score.total, downScoreThreshold - 1));

    return _buildResultFromScore(
      score: displayScore,
      downFrameCount: downFrameCount,
      state: isConfirmedDown ? PostureDownState.down : PostureDownState.normal,
    );
  }

  PostureDownDetectionResult _evaluateScore({
    required _PostureScore score,
    required int previousDownFrameCount,
  }) {
    final isDown = !score.isCalibrating && score.total >= downScoreThreshold;
    if (isDown) {
      _lastDownScore = score;
    }

    if (!isDown && previousDownFrameCount >= downFrames) {
      if (_isClearlyRecovered(score)) {
        _clearDownHold();
        _lastScore = score;
        return _buildResultFromScore(
          score: score,
          downFrameCount: 0,
          state: PostureDownState.normal,
        );
      }

      _recoveryFrameCount++;
      if (_recoveryFrameCount < recoveryFrames) {
        final heldScore = _lastDownScore ?? score;
        _lastScore = heldScore;
        return _buildResultFromScore(
          score: heldScore,
          downFrameCount: previousDownFrameCount,
          state: PostureDownState.down,
        );
      }
    } else {
      _recoveryFrameCount = 0;
    }

    final downFrameCount = isDown ? previousDownFrameCount + 1 : 0;
    _lastScore = score;
    if (downFrameCount >= downFrames) {
      return _buildResultFromScore(
        score: score,
        downFrameCount: downFrameCount,
        state: PostureDownState.down,
      );
    }

    final displayScore = isDown
        ? _withTotal(score, math.min(score.total, downScoreThreshold - 1))
        : score;
    return _buildResultFromScore(
      score: displayScore,
      downFrameCount: downFrameCount,
      state: PostureDownState.normal,
    );
  }

  _PostureScore? _calculateScore(
    VisionResult result, {
    bool shouldUpdate = true,
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

    final headShoulderRatio = (shoulderCenterY - noseY) / shoulderWidth;
    final shoulderWidthRatio = shoulderWidth / imageWidth;
    final shoulderCenterYRatio = shoulderCenterY / imageHeight;
    final noseYRatio = noseY / imageHeight;

    if (_baselineHeadShoulderRatio == null) {
      if (shouldUpdate && result.hasFace) {
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
    );
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
    _missingPoseFrameCount = 0;
    _recoveryFrameCount = 0;
  }

  void _clearDownHold() {
    _lastScore = null;
    _lastDownScore = null;
    _missingPoseFrameCount = 0;
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
      isCalibrating: score.isCalibrating,
    );
  }

  bool _isStrongProneEvidence(_PostureScore score) {
    if (score.isCalibrating || score.total < strongDownScoreThreshold) {
      return false;
    }

    final hasSideProneWithBodyCollapse =
        score.sideProne >= 70 &&
        score.headLow >= 75 &&
        score.noseDrop >= 85 &&
        (score.shoulderDrop >= 45 || score.shoulderShrink >= 70);
    final hasShoulderShrinkProne =
        score.shoulderShrink >= 80 &&
        score.headLow >= 75 &&
        score.noseDrop >= 85;
    final hasFaceMissingShoulderDropEvidence =
        score.sideProne >= 85 && score.shoulderDrop >= 45;
    return hasSideProneWithBodyCollapse ||
        hasShoulderShrinkProne ||
        hasFaceMissingShoulderDropEvidence;
  }

  bool _isClearlyRecovered(_PostureScore score) {
    return score.hasFace &&
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
  final bool isCalibrating;
}
