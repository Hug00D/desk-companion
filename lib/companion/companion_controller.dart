import '../vision/companion_state_evaluator.dart';
import '../vision/dual_track_context_classifier.dart';
import '../vision/eye_state_detector.dart';
import '../vision/posture_down_detector.dart';
import '../vision/vision_result.dart';
import 'return_to_seat_guard.dart';

class CompanionController {
  CompanionController({
    CompanionStateEvaluator? evaluator,
    this.enableDualTrackPilot = false,
    DualTrackContextClassifier? dualTrackClassifier,
  }) : evaluator =
           evaluator ??
           CompanionStateEvaluator(
             postureDownDetector: enableDualTrackPilot
                 ? PostureDownDetector(
                     minimumEvidenceDuration: appPostureConfirmationDuration,
                     maximumEvidenceGap: appMaximumSampleGap,
                     missingEvidenceGraceDuration:
                         appMissingEvidenceGraceDuration,
                   )
                 : null,
           ),
       dualTrackClassifier =
           dualTrackClassifier ??
           DualTrackContextClassifier(
             windowMs: 2000,
             enablePresenceContext: true,
             enableHeadScoreSum: true,
             enableLongShortGate: true,
             maximumSampleGapMs: 1500,
           );

  final CompanionStateEvaluator evaluator;
  final bool enableDualTrackPilot;
  final DualTrackContextClassifier dualTrackClassifier;
  final ReturnToSeatGuard returnToSeatGuard = ReturnToSeatGuard(
    settlingDuration: appReturnSettlingDuration,
    maximumSampleGap: appMaximumSampleGap,
  );
  static const appPostureConfirmationDuration = Duration(milliseconds: 1200);
  static const appMissingEvidenceGraceDuration = Duration(milliseconds: 1500);
  static const appReturnSettlingDuration = Duration(milliseconds: 1500);
  static const appMaximumSampleGap = Duration(milliseconds: 1500);

  int _closedEyeFrameCount = 0;
  int _distractedFrameCount = 0;
  int _postureDownFrameCount = 0;
  int? _lastPoseSequence;
  CompanionAnalysis? _lastAnalysis;
  DualTrackContextResult? _lastDualTrackResult;
  int? _lastDualTrackTimestampMs;
  bool _returnContextCleared = false;

  int get closedEyeFrameCount => _closedEyeFrameCount;
  int get distractedFrameCount => _distractedFrameCount;
  int get postureDownFrameCount => _postureDownFrameCount;
  CompanionAnalysis? get lastAnalysis => _lastAnalysis;
  DualTrackContextResult? get lastDualTrackResult => _lastDualTrackResult;
  CompanionStatus get status => _lastAnalysis?.status ?? CompanionStatus.normal;
  CompanionCause get cause => _lastAnalysis?.cause ?? CompanionCause.none;

  CompanionAnalysis analyze(VisionResult result, {DateTime? observedAt}) {
    final timestamp = observedAt ?? DateTime.now();
    final poseSequence = result.poseSequence;
    final isFreshPoseResult =
        poseSequence != null && poseSequence != _lastPoseSequence;
    final wasAwaitingReturn = returnToSeatGuard.isAwaitingReturn;
    final settlingAfterReturn =
        enableDualTrackPilot &&
        returnToSeatGuard.suppressPosture(
          result,
          freshPose: isFreshPoseResult,
          now: timestamp,
        );
    if (enableDualTrackPilot && wasAwaitingReturn) {
      evaluator.resetPostureTracking();
      if ((!_returnContextCleared && returnToSeatGuard.hasReturnEvidence) ||
          !returnToSeatGuard.isAwaitingReturn) {
        dualTrackClassifier.reset();
        _lastDualTrackTimestampMs = null;
        _returnContextCleared = returnToSeatGuard.isAwaitingReturn;
      }
    }
    final fastAnalysis = evaluator.evaluate(
      result: result,
      previousClosedFrameCount: _closedEyeFrameCount,
      previousDistractedFrameCount: _distractedFrameCount,
      isFreshPoseResult: isFreshPoseResult && !settlingAfterReturn,
      observedAt: timestamp,
    );
    final analysis = enableDualTrackPilot
        ? _applyDualTrack(
            result: result,
            fastAnalysis: fastAnalysis,
            observedAt: timestamp,
          )
        : fastAnalysis;
    _closedEyeFrameCount = fastAnalysis.eyeResult.closedFrameCount;
    _distractedFrameCount = fastAnalysis.headOffsetResult.distractedFrameCount;
    _postureDownFrameCount = fastAnalysis.postureDownResult.downFrameCount;
    if (isFreshPoseResult) {
      _lastPoseSequence = poseSequence;
    }
    _lastAnalysis = analysis;
    if (enableDualTrackPilot &&
        analysis.status == CompanionStatus.userMissing) {
      if (!returnToSeatGuard.isAwaitingReturn) {
        evaluator.resetPostureTracking();
        _returnContextCleared = false;
      }
      returnToSeatGuard.beginReturn();
    } else if (enableDualTrackPilot) {
      returnToSeatGuard.recordSeatedBaseline(
        analysis,
        freshPose: isFreshPoseResult,
      );
    }
    return analysis;
  }

  CompanionAnalysis _applyDualTrack({
    required VisionResult result,
    required CompanionAnalysis fastAnalysis,
    required DateTime? observedAt,
  }) {
    final candidateTimestamp =
        (observedAt ?? DateTime.now()).millisecondsSinceEpoch;
    final timestampMs = _lastDualTrackTimestampMs == null
        ? candidateTimestamp
        : candidateTimestamp > _lastDualTrackTimestampMs!
        ? candidateTimestamp
        : _lastDualTrackTimestampMs! + 1;
    _lastDualTrackTimestampMs = timestampMs;

    final dual = dualTrackClassifier.classify(
      timestampMs: timestampMs,
      result: result,
      fastState: fastAnalysis.state,
      rawEyeClosed:
          fastAnalysis.eyeResult.state == EyeState.attention ||
          fastAnalysis.eyeResult.state == EyeState.fatigue,
      strongPostureEvidence:
          fastAnalysis.status == CompanionStatus.sleeping &&
          fastAnalysis.cause == CompanionCause.postureDown,
      postureScore: fastAnalysis.postureDownResult.score,
    );
    _lastDualTrackResult = dual;
    final state = _stateFromDualTrack(dual, fastAnalysis.state);
    return CompanionAnalysis(
      visionResult: fastAnalysis.visionResult,
      eyeResult: fastAnalysis.eyeResult,
      headOffsetResult: dual.headScore ?? fastAnalysis.headOffsetResult,
      postureDownResult: fastAnalysis.postureDownResult,
      poseResult: fastAnalysis.poseResult,
      presenceState: fastAnalysis.presenceState,
      state: state,
    );
  }

  CompanionState _stateFromDualTrack(
    DualTrackContextResult dual,
    CompanionState fastState,
  ) {
    switch (dual.finalState) {
      case 'posture_down':
        return const CompanionState(
          status: CompanionStatus.sleeping,
          cause: CompanionCause.postureDown,
        );
      case 'drowsy_like':
      case 'sleeping':
        return CompanionState(
          status: CompanionStatus.sleeping,
          cause: fastState.cause == CompanionCause.postureDown
              ? CompanionCause.postureDown
              : CompanionCause.drowsy,
        );
      case 'distracted':
        return const CompanionState(
          status: CompanionStatus.distracted,
          cause: CompanionCause.headTurned,
        );
      case 'user_missing':
        return const CompanionState(
          status: CompanionStatus.userMissing,
          cause: CompanionCause.userAway,
        );
      case 'attention':
        return const CompanionState(
          status: CompanionStatus.attention,
          cause: CompanionCause.eyeClosed,
        );
      case 'fatigue':
        return const CompanionState(
          status: CompanionStatus.fatigue,
          cause: CompanionCause.eyeClosed,
        );
      case 'normal':
      case 'reading_like':
      case 'unknown_low_head':
        return CompanionState.normal;
      default:
        return fastState;
    }
  }

  void reset() {
    _closedEyeFrameCount = 0;
    _distractedFrameCount = 0;
    _postureDownFrameCount = 0;
    _lastPoseSequence = null;
    _lastAnalysis = null;
    _lastDualTrackResult = null;
    _lastDualTrackTimestampMs = null;
    _returnContextCleared = false;
    returnToSeatGuard.reset();
    evaluator.reset();
    dualTrackClassifier.reset();
  }
}
