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
  sleeping,
  userMissing,
}

enum CompanionCause {
  none,
  frequentBlink,
  eyeClosed,
  headTurned,
  drowsy,
  postureDown,
  faceMissing,
  userAway,
}

class CompanionState {
  const CompanionState({required this.status, required this.cause});

  static const CompanionState normal = CompanionState(
    status: CompanionStatus.normal,
    cause: CompanionCause.none,
  );

  final CompanionStatus status;
  final CompanionCause cause;
}

extension CompanionStatusLabel on CompanionStatus {
  String get label {
    switch (this) {
      case CompanionStatus.normal:
        return '狀態：正常';
      case CompanionStatus.attention:
        return '注意：短暫注意力下降';
      case CompanionStatus.fatigue:
        return '疲勞警告：偵測到閉眼';
      case CompanionStatus.distracted:
        return '分心提醒：視線偏離';
      case CompanionStatus.sleeping:
        return '睡眠提醒：疑似睡著';
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
    required this.state,
  });

  final VisionResult visionResult;
  final EyeDetectionResult eyeResult;
  final HeadOffsetDetectionResult headOffsetResult;
  final PostureDownDetectionResult postureDownResult;
  final PoseDetectionResult poseResult;
  final PresenceState presenceState;
  final CompanionState state;

  CompanionStatus get status => state.status;
  CompanionCause get cause => state.cause;

  PoseState get poseState => poseResult.state;
}

class CompanionStateEvaluator {
  CompanionStateEvaluator({
    this.eyeStateDetector = const EyeStateDetector(),
    HeadOffsetDetector? headOffsetDetector,
    PostureDownDetector? postureDownDetector,
    this.poseStateDetector = const PoseStateDetector(),
    this.presenceDetector = const PresenceDetector(),
    this.userAbsentReleaseFrames = 8,
    this.postureDownAbsentReleaseFrames = 25,
    this.faceUprightReleaseFrames = 5,
    this.faceMissingDistractionDuration = const Duration(milliseconds: 900),
    this.strongPostureCandidateHoldFrames = 3,
    this.strongPostureFatigueClosedFrames = 5,
  }) : headOffsetDetector = headOffsetDetector ?? HeadOffsetDetector(),
       postureDownDetector = postureDownDetector ?? PostureDownDetector();

  final EyeStateDetector eyeStateDetector;
  final HeadOffsetDetector headOffsetDetector;
  final PostureDownDetector postureDownDetector;
  final PoseStateDetector poseStateDetector;
  final PresenceDetector presenceDetector;
  final int userAbsentReleaseFrames;
  final int postureDownAbsentReleaseFrames;
  final int faceUprightReleaseFrames;
  final Duration faceMissingDistractionDuration;
  final int strongPostureCandidateHoldFrames;
  final int strongPostureFatigueClosedFrames;
  CompanionStatus _lastFaceVisibleContext = CompanionStatus.normal;
  CompanionStatus? _lastFaceMissingContext;
  DateTime? _faceMissingStartedAt;
  int _recentStableShoulderFrames = 0;
  int _recentLoweredShoulderFrames = 0;
  int _recentHeadDropFrames = 0;
  int _recentDeepHeadDropFrames = 0;
  int _recentPostureDownEvidenceFrames = 0;
  int _recentProneTransitionEvidenceFrames = 0;
  bool _isPostureDownLatched = false;
  int _postureDownRecoveryFrames = 0;
  int _fullyAbsentFrameCount = 0;
  int _faceUprightFrames = 0;
  int _recentStrongPostureCandidateFrames = 0;
  CompanionCause _lastResolvedCause = CompanionCause.none;

  CompanionAnalysis evaluate({
    required VisionResult result,
    required int previousClosedFrameCount,
    required int previousDistractedFrameCount,
    required bool isFreshPoseResult,
    DateTime? observedAt,
  }) {
    final timestamp = observedAt ?? DateTime.now();
    final eyeResult = eyeStateDetector.evaluate(
      result: result,
      previousClosedFrameCount: previousClosedFrameCount,
    );
    final headOffsetResult = headOffsetDetector.evaluate(
      result: result,
      previousDistractedFrameCount: previousDistractedFrameCount,
      observedAt: timestamp,
    );
    final postureDownResult = postureDownDetector.evaluate(
      result: result,
      shouldUpdate: isFreshPoseResult,
      observedAt: timestamp,
    );
    final poseResult = poseStateDetector.evaluate(
      result: result,
      postureDownResult: postureDownResult,
      postureDownFrameCount: postureDownResult.downFrameCount,
      isPostureDown: postureDownResult.state == PostureDownState.down,
      eyeState: eyeResult.state,
    );
    final presenceState = presenceDetector.evaluate(result);
    _updateRecentPoseContext(
      result: result,
      postureDownResult: postureDownResult,
      isFreshPoseResult: isFreshPoseResult,
    );
    _updateStrongPostureCandidateContext(postureDownResult);
    final combinedState = _combine(
      eyeResult: eyeResult,
      headOffsetState: headOffsetResult.state,
      poseState: poseResult.state,
      presenceState: presenceState,
      suppressEyeWarning: _shouldSuppressEyeWarning(
        result: result,
        postureDownResult: postureDownResult,
        eyeResult: eyeResult,
      ),
    );
    final resolvedStatus = _resolveFaceMissingContext(
      result: result,
      postureDownResult: postureDownResult,
      eyeState: eyeResult.state,
      baseStatus: combinedState.status,
      isFreshPoseResult: isFreshPoseResult,
      observedAt: timestamp,
    );
    final resolvedHeadOffsetResult =
        resolvedStatus == CompanionStatus.distracted &&
            headOffsetResult.state != HeadOffsetState.distracted
        ? HeadOffsetDetectionResult(
            state: HeadOffsetState.distracted,
            distractedFrameCount: previousDistractedFrameCount + 1,
          )
        : headOffsetResult;

    final resolvedCause = _causeForResolvedStatus(
      status: resolvedStatus,
      baseState: combinedState,
      result: result,
      eyeState: eyeResult.state,
      poseState: poseResult.state,
      presenceState: presenceState,
    );
    _lastResolvedCause = resolvedCause;

    return CompanionAnalysis(
      visionResult: result,
      eyeResult: eyeResult,
      headOffsetResult: resolvedHeadOffsetResult,
      postureDownResult: postureDownResult,
      poseResult: poseResult,
      presenceState: presenceState,
      state: CompanionState(status: resolvedStatus, cause: resolvedCause),
    );
  }

  CompanionState _combine({
    required EyeDetectionResult eyeResult,
    required HeadOffsetState headOffsetState,
    required PoseState poseState,
    required PresenceState presenceState,
    required bool suppressEyeWarning,
  }) {
    if (poseState == PoseState.postureDown) {
      return const CompanionState(
        status: CompanionStatus.sleeping,
        cause: CompanionCause.postureDown,
      );
    }
    if (poseState == PoseState.drowsy) {
      return const CompanionState(
        status: CompanionStatus.sleeping,
        cause: CompanionCause.drowsy,
      );
    }
    // A side turn can distort eye landmarks. Once head-offset evidence is
    // confirmed, classify it as distraction before considering eye warnings.
    if (headOffsetState == HeadOffsetState.distracted) {
      return const CompanionState(
        status: CompanionStatus.distracted,
        cause: CompanionCause.headTurned,
      );
    }
    if (!suppressEyeWarning) {
      if (eyeResult.state == EyeState.fatigue) {
        return const CompanionState(
          status: CompanionStatus.fatigue,
          cause: CompanionCause.eyeClosed,
        );
      }
      if (eyeResult.state == EyeState.attention) {
        return const CompanionState(
          status: CompanionStatus.attention,
          cause: CompanionCause.eyeClosed,
        );
      }
    }
    if (presenceState == PresenceState.away) {
      return const CompanionState(
        status: CompanionStatus.userMissing,
        cause: CompanionCause.userAway,
      );
    }
    return CompanionState.normal;
  }

  CompanionCause _causeForResolvedStatus({
    required CompanionStatus status,
    required CompanionState baseState,
    required VisionResult result,
    required EyeState eyeState,
    required PoseState poseState,
    required PresenceState presenceState,
  }) {
    switch (status) {
      case CompanionStatus.normal:
        return CompanionCause.none;
      case CompanionStatus.attention:
        if (!result.hasFace || eyeState == EyeState.noFace) {
          return CompanionCause.faceMissing;
        }
        if (baseState.status == CompanionStatus.attention) {
          return baseState.cause;
        }
        if (eyeState == EyeState.attention) {
          return CompanionCause.eyeClosed;
        }
        return CompanionCause.none;
      case CompanionStatus.fatigue:
        return CompanionCause.eyeClosed;
      case CompanionStatus.distracted:
        return CompanionCause.headTurned;
      case CompanionStatus.sleeping:
        if (_isPostureDownLatched ||
            poseState == PoseState.postureDown ||
            baseState.cause == CompanionCause.postureDown) {
          return CompanionCause.postureDown;
        }
        if (poseState == PoseState.drowsy ||
            baseState.cause == CompanionCause.drowsy) {
          return CompanionCause.drowsy;
        }
        if (_lastResolvedCause == CompanionCause.postureDown ||
            _lastResolvedCause == CompanionCause.drowsy) {
          return _lastResolvedCause;
        }
        return CompanionCause.drowsy;
      case CompanionStatus.userMissing:
        return presenceState == PresenceState.away
            ? CompanionCause.userAway
            : CompanionCause.faceMissing;
    }
  }

  bool _shouldSuppressEyeWarning({
    required VisionResult result,
    required PostureDownDetectionResult postureDownResult,
    required EyeDetectionResult eyeResult,
  }) {
    final headOffsetScore = result.headOffsetScore ?? 0;
    final faceIsTurning = headOffsetScore >= 45;
    if (faceIsTurning) return true;

    final hasStrongPostureCandidate =
        _recentStrongPostureCandidateFrames > 0 ||
        _hasStrongPostureCandidate(postureDownResult);
    if (!hasStrongPostureCandidate) return false;

    if (eyeResult.state == EyeState.attention) return true;
    if (eyeResult.state == EyeState.fatigue &&
        eyeResult.closedFrameCount < strongPostureFatigueClosedFrames) {
      return true;
    }
    return false;
  }

  CompanionStatus _resolveFaceMissingContext({
    required VisionResult result,
    required PostureDownDetectionResult postureDownResult,
    required EyeState eyeState,
    required CompanionStatus baseStatus,
    required bool isFreshPoseResult,
    required DateTime observedAt,
  }) {
    if (!result.hasFace && !result.hasPose) {
      _fullyAbsentFrameCount++;
    } else {
      _fullyAbsentFrameCount = 0;
    }
    if (result.hasFace && (result.headPitch?.abs() ?? 0) < 30) {
      _faceUprightFrames++;
    } else {
      _faceUprightFrames = 0;
    }

    final hasStrongPostureDownEvidence = _hasStrongPostureDownEvidence(
      postureDownResult,
    );
    final shouldLatchPostureDown =
        postureDownResult.state == PostureDownState.down;
    if (_isPostureDownLatched &&
        _fullyAbsentFrameCount >= postureDownAbsentReleaseFrames) {
      // The user has been completely out of frame for a long stretch; treat
      // this as leaving the desk instead of holding the prone latch forever.
      _isPostureDownLatched = false;
      _postureDownRecoveryFrames = 0;
      _lastFaceMissingContext = null;
      _lastFaceVisibleContext = CompanionStatus.normal;
      _clearRecentPoseEvidence();
      postureDownDetector.reset();
      return CompanionStatus.userMissing;
    }
    if (_isPostureDownLatched &&
        _faceUprightFrames >= faceUprightReleaseFrames) {
      // A steadily visible, upright face is incompatible with lying on the
      // desk; force-release the latch and recalibrate the posture baseline
      // for the user's new seating position.
      _isPostureDownLatched = false;
      _postureDownRecoveryFrames = 0;
      _lastFaceMissingContext = null;
      _lastFaceVisibleContext = CompanionStatus.normal;
      _clearRecentPoseEvidence();
      postureDownDetector.reset();
      return CompanionStatus.normal;
    }
    if (shouldLatchPostureDown) {
      _isPostureDownLatched = true;
      _postureDownRecoveryFrames = 0;
      _lastFaceVisibleContext = CompanionStatus.sleeping;
      _lastFaceMissingContext = CompanionStatus.sleeping;
      return CompanionStatus.sleeping;
    }

    if (_isPostureDownLatched) {
      if (isFreshPoseResult &&
          _hasClearPostureDownRecovery(
            result: result,
            postureDownResult: postureDownResult,
            eyeState: eyeState,
          )) {
        _postureDownRecoveryFrames++;
        // PostureDownDetector already requires two fresh recovery samples.
        if (_postureDownRecoveryFrames >= 1) {
          _isPostureDownLatched = false;
          _lastFaceMissingContext = null;
          _lastFaceVisibleContext = CompanionStatus.normal;
        } else {
          return CompanionStatus.sleeping;
        }
      } else {
        _postureDownRecoveryFrames = 0;
        _lastFaceMissingContext = CompanionStatus.sleeping;
        return CompanionStatus.sleeping;
      }
    }

    if (result.hasFace) {
      _faceMissingStartedAt = null;
      _lastFaceMissingContext = null;
      final visibleStatus =
          baseStatus == CompanionStatus.sleeping &&
              postureDownResult.state == PostureDownState.down &&
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
      if (baseStatus == CompanionStatus.sleeping &&
          postureDownResult.state == PostureDownState.down &&
          !hasStrongPostureDownEvidence) {
        return visibleStatus;
      }

      return baseStatus;
    }

    if (_fullyAbsentFrameCount >= userAbsentReleaseFrames) {
      // Neither face nor pose for a sustained stretch: the user left the
      // frame, so stop inferring distraction/drowsiness from stale context.
      _lastFaceMissingContext = null;
      _lastFaceVisibleContext = CompanionStatus.normal;
      _clearRecentPoseEvidence();
      return CompanionStatus.userMissing;
    }

    final shoulderDropScore = postureDownResult.shoulderDropScore ?? 0;
    final shoulderShrinkScore = postureDownResult.shoulderShrinkScore ?? 0;
    final headLowScore = postureDownResult.headLowScore ?? 0;
    final noseDropScore = postureDownResult.noseDropScore ?? 0;
    final headDropLikely = headLowScore >= 40 && noseDropScore >= 30;
    final currentShouldersNearBaseline =
        result.hasPose && shoulderDropScore < 18 && shoulderShrinkScore < 35;
    final shouldersNearBaseline =
        result.hasPose &&
        (currentShouldersNearBaseline || _recentStableShoulderFrames > 0);
    final hasRecentProneEvidence =
        _recentPostureDownEvidenceFrames > 0 ||
        _recentProneTransitionEvidenceFrames > 0;
    if (_lastFaceVisibleContext == CompanionStatus.sleeping &&
        !hasRecentProneEvidence) {
      _lastFaceMissingContext = CompanionStatus.sleeping;
      return CompanionStatus.sleeping;
    }

    if (shouldersNearBaseline) {
      if (_lastFaceVisibleContext == CompanionStatus.sleeping) {
        _faceMissingStartedAt = null;
        _lastFaceMissingContext = CompanionStatus.sleeping;
        return CompanionStatus.sleeping;
      }
      if (headDropLikely) {
        if (_hasStableReadingBody(postureDownResult) &&
            headLowScore < _readingProtectionHeadLowMax) {
          _faceMissingStartedAt = null;
          _lastFaceMissingContext = null;
          return baseStatus;
        }
        _faceMissingStartedAt = null;
        _lastFaceMissingContext = CompanionStatus.attention;
        return CompanionStatus.attention;
      }
      _faceMissingStartedAt ??= observedAt;
      if (observedAt.difference(_faceMissingStartedAt!) >=
          faceMissingDistractionDuration) {
        // A large side turn often makes Face Landmarker lose the face while
        // Pose still sees stable shoulders. Use elapsed time so camera and
        // fallback-video sampling rates produce the same behavior.
        _lastFaceMissingContext = CompanionStatus.distracted;
        return CompanionStatus.distracted;
      }
      _lastFaceMissingContext = null;
      return baseStatus;
    }

    _faceMissingStartedAt = null;
    if (!result.hasPose && _lastFaceMissingContext != null) {
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
        shoulderShrinkScore >= 80 && headLowScore >= 75 && noseDropScore >= 43;
    final strongShoulderDropProne =
        sideProneScore >= 85 && shoulderDropScore >= 45;
    final strongSideProne =
        sideProneScore >= 70 &&
        shoulderShrinkScore >= 70 &&
        noseDropScore >= 43;

    return strongShoulderShrinkProne ||
        strongShoulderDropProne ||
        strongSideProne;
  }

  void _updateStrongPostureCandidateContext(
    PostureDownDetectionResult postureDownResult,
  ) {
    if (_hasStrongPostureCandidate(postureDownResult)) {
      _recentStrongPostureCandidateFrames = strongPostureCandidateHoldFrames;
    } else if (_recentStrongPostureCandidateFrames > 0) {
      _recentStrongPostureCandidateFrames--;
    }
  }

  bool _hasStrongPostureCandidate(
    PostureDownDetectionResult postureDownResult,
  ) {
    final score = postureDownResult.score ?? 0;
    final sideProneScore = postureDownResult.sideProneScore ?? 0;
    final shoulderDropScore = postureDownResult.shoulderDropScore ?? 0;
    final shoulderShrinkScore = postureDownResult.shoulderShrinkScore ?? 0;
    final headLowScore = postureDownResult.headLowScore ?? 0;
    final noseDropScore = postureDownResult.noseDropScore ?? 0;
    final bodyMoved =
        shoulderDropScore >= 34 ||
        shoulderShrinkScore >= 55 ||
        sideProneScore >= 65;
    final strongHeadDrop =
        headLowScore >= 70 && noseDropScore >= 40 && bodyMoved;

    return shoulderDropScore >= 60 ||
        shoulderShrinkScore >= 70 ||
        sideProneScore >= 75 ||
        strongHeadDrop ||
        (postureDownResult.downFrameCount > 0 && score >= 70);
  }

  bool _hasClearPostureDownRecovery({
    required VisionResult result,
    required PostureDownDetectionResult postureDownResult,
    required EyeState eyeState,
  }) {
    if (!result.hasPose) return false;

    final score = postureDownResult.score ?? 0;
    final sideProneScore = postureDownResult.sideProneScore ?? 0;
    final shoulderDropScore = postureDownResult.shoulderDropScore ?? 0;
    final shoulderShrinkScore = postureDownResult.shoulderShrinkScore ?? 0;
    final headLowScore = postureDownResult.headLowScore ?? 0;
    final noseDropScore = postureDownResult.noseDropScore ?? 0;

    if (!result.hasFace) {
      // Body is back upright but the face has not been re-acquired yet
      // (e.g. head turned). Require every posture score to be clearly back
      // to baseline before releasing the latch.
      return postureDownResult.state != PostureDownState.down &&
          sideProneScore < 40 &&
          shoulderDropScore < 25 &&
          shoulderShrinkScore < 35 &&
          headLowScore < 50 &&
          noseDropScore < 28;
    }

    final headPitch = result.headPitch?.abs() ?? 0;
    final headOffsetScore = result.headOffsetScore ?? 0;
    final faceVisibleStableRecovery =
        eyeState == EyeState.open &&
        sideProneScore < 45 &&
        shoulderShrinkScore < 45 &&
        headLowScore < 45 &&
        noseDropScore < 30 &&
        headPitch < 25 &&
        headOffsetScore < 35;

    return faceVisibleStableRecovery ||
        score < 30 &&
            sideProneScore < 45 &&
            shoulderDropScore < 35 &&
            shoulderShrinkScore < 45 &&
            headLowScore < 45 &&
            noseDropScore < 30;
  }

  void _updateRecentPoseContext({
    required VisionResult result,
    required PostureDownDetectionResult postureDownResult,
    required bool isFreshPoseResult,
  }) {
    if (!isFreshPoseResult) return;
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

      if (headLowScore >= 40 && noseDropScore >= 30) {
        _recentHeadDropFrames = 8;
      } else if (_recentHeadDropFrames > 0) {
        _recentHeadDropFrames--;
      }

      if (headLowScore >= 75 && noseDropScore >= 45) {
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

    final headCollapsed = headLowScore >= 70 && noseDropScore >= 45;
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
    if (baseStatus == CompanionStatus.sleeping ||
        baseStatus == CompanionStatus.distracted) {
      return baseStatus;
    }

    final headPitch = result.headPitch?.abs() ?? 0;
    final headLowScore = postureDownResult.headLowScore ?? 0;
    final noseDropScore = postureDownResult.noseDropScore ?? 0;
    final pitchSupportsHeadDrop =
        headPitch >= 26 && (headLowScore >= 35 || noseDropScore >= 20);
    final geometrySupportsHeadDrop = headLowScore >= 45 && noseDropScore >= 28;
    if (pitchSupportsHeadDrop || geometrySupportsHeadDrop) {
      if (_hasStableReadingBody(postureDownResult) &&
          headLowScore < _readingProtectionHeadLowMax) {
        return baseStatus;
      }
      return eyeState == EyeState.fatigue
          ? CompanionStatus.sleeping
          : CompanionStatus.attention;
    }

    final headOffsetScore = result.headOffsetScore ?? 0;
    if (headOffsetScore >= 55) {
      return CompanionStatus.distracted;
    }

    return CompanionStatus.normal;
  }

  bool _hasStableReadingBody(PostureDownDetectionResult postureDownResult) {
    final postureDownScore = postureDownResult.score ?? 0;
    final shoulderDropScore = postureDownResult.shoulderDropScore ?? 0;
    final shoulderShrinkScore = postureDownResult.shoulderShrinkScore ?? 0;
    final sideProneScore = postureDownResult.sideProneScore ?? 0;

    return postureDownResult.downFrameCount == 0 &&
        postureDownScore < _readingProtectionPostureScoreMax &&
        shoulderDropScore < _readingProtectionShoulderDropMax &&
        shoulderShrinkScore < _readingProtectionShoulderShrinkMax &&
        sideProneScore < _readingProtectionSideProneMax;
  }

  static const double _readingProtectionHeadLowMax = 95;
  static const double _readingProtectionPostureScoreMax = 35;
  static const double _readingProtectionShoulderDropMax = 24;
  static const double _readingProtectionShoulderShrinkMax = 25;
  static const double _readingProtectionSideProneMax = 30;

  void _clearRecentPoseEvidence() {
    _recentStableShoulderFrames = 0;
    _recentLoweredShoulderFrames = 0;
    _recentHeadDropFrames = 0;
    _recentDeepHeadDropFrames = 0;
    _recentPostureDownEvidenceFrames = 0;
    _recentProneTransitionEvidenceFrames = 0;
    _recentStrongPostureCandidateFrames = 0;
  }

  void reset() {
    headOffsetDetector.reset();
    postureDownDetector.reset();
    _lastFaceVisibleContext = CompanionStatus.normal;
    _lastFaceMissingContext = null;
    _faceMissingStartedAt = null;
    _clearRecentPoseEvidence();
    _isPostureDownLatched = false;
    _postureDownRecoveryFrames = 0;
    _fullyAbsentFrameCount = 0;
    _faceUprightFrames = 0;
    _recentStrongPostureCandidateFrames = 0;
    _lastResolvedCause = CompanionCause.none;
  }
}
