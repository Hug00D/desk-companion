import 'eye_state_detector.dart';
import 'head_offset_detector.dart';
import 'pose_state_detector.dart';
import 'posture_down_detector.dart';
import 'presence_detector.dart';
import 'vision_result.dart';

enum CompanionStatus {
  normal,
  attention,
  fatigue,
  distracted,
  drowsy,
  postureDown,
  userMissing,
}

extension CompanionStatusLabel on CompanionStatus {
  String get label {
    switch (this) {
      case CompanionStatus.normal:
        return '狀態：正常';
      case CompanionStatus.attention:
        return '注意：眨眼頻繁';
      case CompanionStatus.fatigue:
        return '疲勞警告：偵測到閉眼';
      case CompanionStatus.distracted:
        return '分心提醒：視線偏離';
      case CompanionStatus.drowsy:
        return '低頭打瞌睡';
      case CompanionStatus.postureDown:
        return '趴下睡覺';
      case CompanionStatus.userMissing:
        return '尚未偵測到完整使用者';
    }
  }
}

class CompanionAnalysis {
  const CompanionAnalysis({
    required this.visionResult,
    required this.eyeResult,
    required this.headOffsetResult,
    required this.postureDownResult,
    required this.poseResult,
    required this.presenceState,
    required this.status,
  });

  final VisionResult visionResult;
  final EyeDetectionResult eyeResult;
  final HeadOffsetDetectionResult headOffsetResult;
  final PostureDownDetectionResult postureDownResult;
  final PoseDetectionResult poseResult;
  final PresenceState presenceState;
  final CompanionStatus status;

  PoseState get poseState => poseResult.state;
}

class CompanionStateEvaluator {
  CompanionStateEvaluator({
    this.eyeStateDetector = const EyeStateDetector(),
    HeadOffsetDetector? headOffsetDetector,
    PostureDownDetector? postureDownDetector,
    this.poseStateDetector = const PoseStateDetector(),
    this.presenceDetector = const PresenceDetector(),
  }) : headOffsetDetector = headOffsetDetector ?? HeadOffsetDetector(),
       postureDownDetector = postureDownDetector ?? PostureDownDetector();

  final EyeStateDetector eyeStateDetector;
  final HeadOffsetDetector headOffsetDetector;
  final PostureDownDetector postureDownDetector;
  final PoseStateDetector poseStateDetector;
  final PresenceDetector presenceDetector;
  CompanionStatus _lastFaceVisibleContext = CompanionStatus.normal;
  CompanionStatus? _lastFaceMissingContext;
  int _faceMissingFrameCount = 0;
  int _recentStableShoulderFrames = 0;
  int _recentLoweredShoulderFrames = 0;
  int _recentHeadDropFrames = 0;
  int _recentDeepHeadDropFrames = 0;
  int _recentPostureDownEvidenceFrames = 0;
  int _recentProneTransitionEvidenceFrames = 0;
  bool _isPostureDownLatched = false;
  int _postureDownRecoveryFrames = 0;

  CompanionAnalysis evaluate({
    required VisionResult result,
    required int previousClosedFrameCount,
    required int previousDistractedFrameCount,
    required int previousPostureDownFrameCount,
    required bool shouldUpdatePostureDown,
  }) {
    final eyeResult = eyeStateDetector.evaluate(
      result: result,
      previousClosedFrameCount: previousClosedFrameCount,
    );
    final headOffsetResult = headOffsetDetector.evaluate(
      result: result,
      previousDistractedFrameCount: previousDistractedFrameCount,
    );
    final postureDownResult = postureDownDetector.evaluate(
      result: result,
      previousDownFrameCount: previousPostureDownFrameCount,
      shouldUpdate: shouldUpdatePostureDown,
    );
    final poseResult = poseStateDetector.evaluate(
      result: result,
      postureDownResult: postureDownResult,
      postureDownFrameCount: postureDownResult.downFrameCount,
      isPostureDown: postureDownResult.state == PostureDownState.down,
    );
    final presenceState = presenceDetector.evaluate(result);
    _updateRecentPoseContext(
      result: result,
      postureDownResult: postureDownResult,
    );
    final combinedStatus = _combine(
      eyeState: eyeResult.state,
      headOffsetState: headOffsetResult.state,
      poseState: poseResult.state,
      presenceState: presenceState,
    );
    final resolvedStatus = _resolveFaceMissingContext(
      result: result,
      postureDownResult: postureDownResult,
      eyeState: eyeResult.state,
      baseStatus: combinedStatus,
    );
    final resolvedHeadOffsetResult =
        resolvedStatus == CompanionStatus.distracted &&
            headOffsetResult.state != HeadOffsetState.distracted
        ? HeadOffsetDetectionResult(
            state: HeadOffsetState.distracted,
            distractedFrameCount: previousDistractedFrameCount + 1,
          )
        : headOffsetResult;

    return CompanionAnalysis(
      visionResult: result,
      eyeResult: eyeResult,
      headOffsetResult: resolvedHeadOffsetResult,
      postureDownResult: postureDownResult,
      poseResult: poseResult,
      presenceState: presenceState,
      status: resolvedStatus,
    );
  }

  CompanionStatus _combine({
    required EyeState eyeState,
    required HeadOffsetState headOffsetState,
    required PoseState poseState,
    required PresenceState presenceState,
  }) {
    if (poseState == PoseState.postureDown) return CompanionStatus.postureDown;
    if (poseState == PoseState.drowsy) return CompanionStatus.drowsy;
    if (eyeState == EyeState.fatigue) return CompanionStatus.fatigue;
    if (eyeState == EyeState.attention) return CompanionStatus.attention;
    if (headOffsetState == HeadOffsetState.distracted) {
      return CompanionStatus.distracted;
    }
    if (presenceState == PresenceState.away) return CompanionStatus.userMissing;
    return CompanionStatus.normal;
  }

  CompanionStatus _resolveFaceMissingContext({
    required VisionResult result,
    required PostureDownDetectionResult postureDownResult,
    required EyeState eyeState,
    required CompanionStatus baseStatus,
  }) {
    final hasStrongPostureDownEvidence = _hasStrongPostureDownEvidence(
      postureDownResult,
    );
    final shouldLatchPostureDown = hasStrongPostureDownEvidence;
    if (shouldLatchPostureDown) {
      _isPostureDownLatched = true;
      _postureDownRecoveryFrames = 0;
      _lastFaceVisibleContext = CompanionStatus.postureDown;
      _lastFaceMissingContext = CompanionStatus.postureDown;
      return CompanionStatus.postureDown;
    }

    if (_isPostureDownLatched) {
      if (_hasClearPostureDownRecovery(
        result: result,
        postureDownResult: postureDownResult,
      )) {
        _postureDownRecoveryFrames++;
        if (_postureDownRecoveryFrames >= 1) {
          _isPostureDownLatched = false;
          _lastFaceMissingContext = null;
          _lastFaceVisibleContext = CompanionStatus.normal;
        } else {
          return CompanionStatus.postureDown;
        }
      } else {
        _postureDownRecoveryFrames = 0;
        _lastFaceMissingContext = CompanionStatus.postureDown;
        return CompanionStatus.postureDown;
      }
    }

    if (result.hasFace) {
      if (!result.hasPose &&
          (_recentPostureDownEvidenceFrames > 0 ||
              _recentProneTransitionEvidenceFrames > 0)) {
        _isPostureDownLatched = true;
        _postureDownRecoveryFrames = 0;
        return CompanionStatus.postureDown;
      }
      if (!result.hasPose && _recentDeepHeadDropFrames > 0) {
        _isPostureDownLatched = true;
        _postureDownRecoveryFrames = 0;
        _lastFaceMissingContext = CompanionStatus.postureDown;
        return CompanionStatus.postureDown;
      }

      _faceMissingFrameCount = 0;
      _lastFaceMissingContext = null;
      final visibleStatus =
          baseStatus == CompanionStatus.postureDown &&
              !hasStrongPostureDownEvidence
          ? _faceVisibleContext(
              result: result,
              postureDownResult: postureDownResult,
              eyeState: eyeState,
              baseStatus: CompanionStatus.normal,
            )
          : baseStatus;
      _lastFaceVisibleContext = _faceVisibleContext(
        result: result,
        postureDownResult: postureDownResult,
        eyeState: eyeState,
        baseStatus: visibleStatus,
      );
      if (baseStatus == CompanionStatus.postureDown &&
          !hasStrongPostureDownEvidence) {
        return visibleStatus == CompanionStatus.postureDown
            ? CompanionStatus.drowsy
            : visibleStatus;
      }

      return baseStatus;
    }

    _faceMissingFrameCount++;

    final shoulderDropScore = postureDownResult.shoulderDropScore ?? 0;
    final shoulderShrinkScore = postureDownResult.shoulderShrinkScore ?? 0;
    final headLowScore = postureDownResult.headLowScore ?? 0;
    final noseDropScore = postureDownResult.noseDropScore ?? 0;
    final headDropLikely = headLowScore >= 40 && noseDropScore >= 60;
    final currentShouldersNearBaseline =
        result.hasPose && shoulderDropScore < 18 && shoulderShrinkScore < 35;
    final shouldersNearBaseline =
        currentShouldersNearBaseline || _recentStableShoulderFrames > 0;
    final hasRecentProneEvidence =
        _recentPostureDownEvidenceFrames > 0 ||
        _recentProneTransitionEvidenceFrames > 0;
    final recentlyHeadDropped = _recentHeadDropFrames > 0;
    final recentlyDeepHeadDropped = _recentDeepHeadDropFrames > 0;

    if (!result.hasPose &&
        recentlyHeadDropped &&
        hasRecentProneEvidence &&
        _faceMissingFrameCount >= 2) {
      _isPostureDownLatched = true;
      _postureDownRecoveryFrames = 0;
      return CompanionStatus.postureDown;
    }

    if (!result.hasPose &&
        recentlyDeepHeadDropped &&
        _faceMissingFrameCount >= 2) {
      _isPostureDownLatched = true;
      _postureDownRecoveryFrames = 0;
      _lastFaceMissingContext = CompanionStatus.postureDown;
      return CompanionStatus.postureDown;
    }

    if (_lastFaceVisibleContext == CompanionStatus.drowsy &&
        !hasRecentProneEvidence) {
      _lastFaceMissingContext = CompanionStatus.drowsy;
      return CompanionStatus.drowsy;
    }

    if (shouldersNearBaseline) {
      final inferred =
          _lastFaceVisibleContext == CompanionStatus.drowsy
          ? CompanionStatus.drowsy
          : headDropLikely
          ? CompanionStatus.attention
          : CompanionStatus.distracted;
      _lastFaceMissingContext = inferred;
      return inferred;
    }

    if (!result.hasPose && _lastFaceMissingContext != null) {
      if (_lastFaceMissingContext == CompanionStatus.drowsy &&
          _faceMissingFrameCount >= 4 &&
          hasRecentProneEvidence) {
        _lastFaceMissingContext = CompanionStatus.postureDown;
        return CompanionStatus.postureDown;
      }
      return _lastFaceMissingContext!;
    }

    return baseStatus;
  }

  bool _hasStrongPostureDownEvidence(
    PostureDownDetectionResult postureDownResult,
  ) {
    final sideProneScore = postureDownResult.sideProneScore ?? 0;
    final shoulderDropScore = postureDownResult.shoulderDropScore ?? 0;
    final shoulderShrinkScore = postureDownResult.shoulderShrinkScore ?? 0;
    final headLowScore = postureDownResult.headLowScore ?? 0;
    final noseDropScore = postureDownResult.noseDropScore ?? 0;

    final strongShoulderShrinkProne =
        shoulderShrinkScore >= 80 && headLowScore >= 75 && noseDropScore >= 85;
    final strongShoulderDropProne =
        sideProneScore >= 85 && shoulderDropScore >= 45;
    final strongSideProne =
        sideProneScore >= 70 &&
        shoulderShrinkScore >= 70 &&
        noseDropScore >= 85;

    return strongShoulderShrinkProne ||
        strongShoulderDropProne ||
        strongSideProne;
  }

  bool _hasClearPostureDownRecovery({
    required VisionResult result,
    required PostureDownDetectionResult postureDownResult,
  }) {
    if (!result.hasFace || !result.hasPose) return false;

    final score = postureDownResult.score ?? 0;
    final sideProneScore = postureDownResult.sideProneScore ?? 0;
    final shoulderDropScore = postureDownResult.shoulderDropScore ?? 0;
    final shoulderShrinkScore = postureDownResult.shoulderShrinkScore ?? 0;
    final headLowScore = postureDownResult.headLowScore ?? 0;
    final noseDropScore = postureDownResult.noseDropScore ?? 0;

    return score < 30 &&
        sideProneScore < 45 &&
        shoulderDropScore < 35 &&
        shoulderShrinkScore < 45 &&
        headLowScore < 45 &&
        noseDropScore < 60;
  }

  void _updateRecentPoseContext({
    required VisionResult result,
    required PostureDownDetectionResult postureDownResult,
  }) {
    final shoulderDropScore = postureDownResult.shoulderDropScore;
    final shoulderShrinkScore = postureDownResult.shoulderShrinkScore;
    final headLowScore = postureDownResult.headLowScore;
    final noseDropScore = postureDownResult.noseDropScore;
    if (result.hasPose &&
        shoulderDropScore != null &&
        shoulderShrinkScore != null &&
        headLowScore != null &&
        noseDropScore != null) {
      if (shoulderDropScore < 18 && shoulderShrinkScore < 35) {
        _recentStableShoulderFrames = 8;
      } else if (_recentStableShoulderFrames > 0) {
        _recentStableShoulderFrames--;
      }

      if (shoulderDropScore >= 24 && shoulderShrinkScore < 45) {
        _recentLoweredShoulderFrames = 8;
      } else if (_recentLoweredShoulderFrames > 0) {
        _recentLoweredShoulderFrames--;
      }

      if (headLowScore >= 40 && noseDropScore >= 60) {
        _recentHeadDropFrames = 8;
      } else if (_recentHeadDropFrames > 0) {
        _recentHeadDropFrames--;
      }

      if (headLowScore >= 75 && noseDropScore >= 90) {
        _recentDeepHeadDropFrames = 20;
      } else if (_recentDeepHeadDropFrames > 0) {
        _recentDeepHeadDropFrames--;
      }

      if (_hasStrongPostureDownEvidence(postureDownResult)) {
        _recentPostureDownEvidenceFrames = 20;
      } else if (_recentPostureDownEvidenceFrames > 0) {
        _recentPostureDownEvidenceFrames--;
      }

      if (_hasProneTransitionEvidence(postureDownResult)) {
        _recentProneTransitionEvidenceFrames = 20;
      } else if (_recentProneTransitionEvidenceFrames > 0) {
        _recentProneTransitionEvidenceFrames--;
      }
      return;
    }

    if (_recentStableShoulderFrames > 0) {
      _recentStableShoulderFrames--;
    }
    if (_recentLoweredShoulderFrames > 0) {
      _recentLoweredShoulderFrames--;
    }
    if (_recentHeadDropFrames > 0) {
      _recentHeadDropFrames--;
    }
    if (_recentDeepHeadDropFrames > 0) {
      _recentDeepHeadDropFrames--;
    }
    if (_recentPostureDownEvidenceFrames > 0) {
      _recentPostureDownEvidenceFrames--;
    }
    if (_recentProneTransitionEvidenceFrames > 0) {
      _recentProneTransitionEvidenceFrames--;
    }
  }

  bool _hasProneTransitionEvidence(
    PostureDownDetectionResult postureDownResult,
  ) {
    final shoulderDropScore = postureDownResult.shoulderDropScore ?? 0;
    final shoulderShrinkScore = postureDownResult.shoulderShrinkScore ?? 0;
    final sideProneScore = postureDownResult.sideProneScore ?? 0;
    final headLowScore = postureDownResult.headLowScore ?? 0;
    final noseDropScore = postureDownResult.noseDropScore ?? 0;

    final headCollapsed = headLowScore >= 70 && noseDropScore >= 90;
    final bodyMoved =
        shoulderDropScore >= 34 ||
        shoulderShrinkScore >= 55 ||
        (sideProneScore >= 90 && shoulderDropScore >= 40);
    return headCollapsed && bodyMoved;
  }

  CompanionStatus _faceVisibleContext({
    required VisionResult result,
    required PostureDownDetectionResult postureDownResult,
    required EyeState eyeState,
    required CompanionStatus baseStatus,
  }) {
    if (baseStatus == CompanionStatus.drowsy ||
        baseStatus == CompanionStatus.postureDown ||
        baseStatus == CompanionStatus.distracted) {
      return baseStatus;
    }

    final headPitch = result.headPitch ?? 0;
    final headLowScore = postureDownResult.headLowScore ?? 0;
    final noseDropScore = postureDownResult.noseDropScore ?? 0;
    if (headPitch >= 28 || (headLowScore >= 65 && noseDropScore >= 70)) {
      return eyeState == EyeState.fatigue
          ? CompanionStatus.drowsy
          : CompanionStatus.attention;
    }

    final headOffsetScore = result.headOffsetScore ?? 0;
    if (headOffsetScore >= 35) {
      return CompanionStatus.distracted;
    }

    return CompanionStatus.normal;
  }

  void reset() {
    headOffsetDetector.reset();
    postureDownDetector.reset();
    _lastFaceVisibleContext = CompanionStatus.normal;
    _lastFaceMissingContext = null;
    _faceMissingFrameCount = 0;
    _recentStableShoulderFrames = 0;
    _recentLoweredShoulderFrames = 0;
    _recentHeadDropFrames = 0;
    _recentDeepHeadDropFrames = 0;
    _recentPostureDownEvidenceFrames = 0;
    _recentProneTransitionEvidenceFrames = 0;
    _isPostureDownLatched = false;
    _postureDownRecoveryFrames = 0;
  }
}
