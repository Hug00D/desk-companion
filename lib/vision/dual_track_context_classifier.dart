import 'dart:math' as math;

import 'companion_state_evaluator.dart';
import 'disappearance_context_classifier.dart';
import 'eye_state_detector.dart';
import 'head_offset_detector.dart';
import 'vision_result.dart';

enum SlowContextState {
  none('none'),
  readingLike('reading_like'),
  drowsyLike('drowsy_like'),
  unknownLowHead('unknown_low_head');

  const SlowContextState(this.csvValue);
  final String csvValue;
}

enum LongHeadContext {
  upright('upright'),
  observingLowHead('observing_low_head'),
  stableLowHead('stable_low_head'),
  variableLowHead('variable_low_head'),
  possibleDrowsy('possible_drowsy'),
  insufficientData('insufficient_data');

  const LongHeadContext(this.csvValue);
  final String csvValue;
}

class DualTrackContextResult {
  const DualTrackContextResult({
    required this.lowHeadCandidate,
    required this.slowState,
    required this.slowWindowMs,
    required this.evidenceEye,
    required this.evidenceMotion,
    required this.evidencePosture,
    required this.dataQuality,
    required this.finalState,
    required this.eyeCoverage,
    required this.poseCoverage,
    required this.closedDurationMs,
    required this.noseDrop,
    required this.pitchRange,
    required this.noseRange,
    required this.motionEvidenceAtMs,
    required this.eyeDescentAtMs,
    required this.drowsyConfirmed,
    required this.longContext,
    required this.shortTrigger,
    required this.sleepLatched,
    required this.postureScore,
    required this.staticDeepPostureMs,
    this.disappearance,
    this.headScore,
  });

  final bool lowHeadCandidate;
  final SlowContextState slowState;
  final int slowWindowMs;
  final bool evidenceEye;
  final bool evidenceMotion;
  final bool evidencePosture;
  final String dataQuality;
  final String finalState;
  final double eyeCoverage;
  final double poseCoverage;
  final int closedDurationMs;
  final double? noseDrop;
  final double? pitchRange;
  final double? noseRange;
  final int? motionEvidenceAtMs;
  final int? eyeDescentAtMs;
  final bool drowsyConfirmed;
  final LongHeadContext longContext;
  final String shortTrigger;
  final bool sleepLatched;
  final double? postureScore;
  final int staticDeepPostureMs;
  final DisappearanceContextResult? disappearance;
  final HeadOffsetDetectionResult? headScore;
}

/// Dual-track candidate shared by offline replay and the explicitly enabled
/// formal-app pilot. Durations use source PTS offline and monotonic observation
/// time in the app; head sums use five samples.
class DualTrackContextClassifier {
  DualTrackContextClassifier({
    this.windowMs = 2000,
    this.enablePresenceContext = false,
    this.enableHeadScoreSum = false,
    this.enableLongShortGate = false,
    this.maximumSampleGapMs = defaultMaximumSampleGapMs,
  }) : _disappearance = DisappearanceContextClassifier(
         maximumGapMs: maximumSampleGapMs,
       ),
       _headScoreDetector = HeadOffsetDetector(
         useScoreSum: true,
         scoreSumMaximumGap: Duration(milliseconds: maximumSampleGapMs),
       ) {
    if (windowMs != 2000 && windowMs != 3000) {
      throw ArgumentError.value(windowMs, 'windowMs', 'Use 2000 or 3000.');
    }
    if (enableHeadScoreSum && !enablePresenceContext) {
      throw ArgumentError('Head score sum requires presence context.');
    }
    if (maximumSampleGapMs <= 0) {
      throw ArgumentError.value(
        maximumSampleGapMs,
        'maximumSampleGapMs',
        'Must be positive.',
      );
    }
  }

  final int windowMs;
  final bool enablePresenceContext;
  final bool enableHeadScoreSum;
  final bool enableLongShortGate;
  final int maximumSampleGapMs;
  final DisappearanceContextClassifier _disappearance;
  final HeadOffsetDetector _headScoreDetector;
  int _headDistractedFrames = 0;
  static const baselineDurationMs = 500;
  static const recoveryDurationMs = 500;
  static const defaultMaximumSampleGapMs = 500;
  static const closureDurationMs = 300;
  static const closureExpiryMs = 2000;
  static const descentDurationMs = 500;
  static const minimumVisibility = 0.5;
  static const minimumCoverage = 0.8;
  static const lowHeadNoseDrop = 0.06;
  static const stableNoseRange = 0.015;
  static const stablePitchRange = 3.0;
  static const uprightPitch = 15.0;
  static const staticDeepPostureScoreThreshold = 80.0;
  static const staticDeepPostureDurationMs = 1000;
  static const _eyeDetector = EyeStateDetector();

  final List<_Sample> _history = [];
  final List<double> _baselineSamples = [];
  int? _baselineSince;
  double? _baselineNose;
  int? _lastTimestamp;
  int? _lowSince;
  int? _recoverySince;
  int? _closedSince;
  int? _armedAt;
  int? _eyeDescentAt;
  int? _motionAt;
  int? _fullyMissingWhileLatchedSince;
  int? _lowHeadRecoverySince;
  int? _staticDeepPostureSince;
  bool _confirmedDrowsy = false;
  bool _confirmedEyeEvidence = false;
  bool _sleepLatched = false;
  bool _staticDeepPostureLatched = false;
  SlowContextState _slowState = SlowContextState.none;

  DualTrackContextResult classify({
    required int timestampMs,
    required VisionResult result,
    required CompanionState fastState,
    required bool rawEyeClosed,
    bool strongPostureEvidence = false,
    double? postureScore,
  }) {
    if (timestampMs < 0 ||
        (_lastTimestamp != null && timestampMs <= _lastTimestamp!)) {
      throw ArgumentError('timestampMs must be non-negative and increasing.');
    }
    if (_lastTimestamp != null &&
        timestampMs - _lastTimestamp! > maximumSampleGapMs) {
      _clearEpisode();
      _history.clear();
      _baselineSince = null;
      _baselineSamples.clear();
    }
    _lastTimestamp = timestampMs;

    final poseReliable = hasReliablePoseGeometry(result);
    final matureLowHeadBeforeLoss =
        _lowSince != null && timestampMs - _lowSince! >= windowMs;
    final disappearance = enablePresenceContext
        ? _disappearance.classify(
            timestampMs: timestampMs,
            result: result,
            reliablePose: poseReliable,
            confirmedSleepPosture: strongPostureEvidence,
            matureLowHeadBeforeLoss: matureLowHeadBeforeLoss,
          )
        : null;
    HeadOffsetDetectionResult? headScore;
    if (enableHeadScoreSum) {
      final blocked =
          strongPostureEvidence ||
          fastState.status == CompanionStatus.userMissing ||
          disappearance!.state == DisappearanceState.away ||
          disappearance.sideExit ||
          disappearance.relativeDescent;
      if (blocked) {
        _headScoreDetector.reset();
        headScore = const HeadOffsetDetectionResult(
          state: HeadOffsetState.unavailable,
          distractedFrameCount: 0,
          scoreSum: 0,
        );
      } else {
        headScore = _headScoreDetector.evaluate(
          result: result,
          previousDistractedFrameCount: _headDistractedFrames,
          observedAt: DateTime.fromMillisecondsSinceEpoch(
            timestampMs,
            isUtc: true,
          ),
          allowMissingFaceFill: poseReliable,
        );
      }
      _headDistractedFrames = headScore.distractedFrameCount;
    }
    final distracted = enableHeadScoreSum
        ? headScore!.state == HeadOffsetState.distracted
        : fastState.status == CompanionStatus.distracted;
    final personMaskPresent =
        result.personPresenceSampled && result.personPresent == true;
    final presenceOverride = personMaskPresent
        ? null
        : switch (disappearance?.state) {
            DisappearanceState.away => 'user_missing',
            DisappearanceState.sleepCandidate =>
              disappearance!.sleepSupported ? 'sleeping' : 'unknown_low_head',
            DisappearanceState.pending || DisappearanceState.unknown =>
              distracted ? 'distracted' : 'unknown_low_head',
            _ => null,
          };
    final nose = poseReliable ? result.poseNoseY! / result.imageHeight! : null;
    final pitch = result.hasFace ? result.headPitch : null;
    final headReliable =
        result.hasFace &&
        pitch != null &&
        pitch.isFinite &&
        result.headOffsetScore != null &&
        result.headOffsetScore!.isFinite &&
        !result.isHeadOffsetCalibrating &&
        pitch.abs() <= _eyeDetector.maxReliableHeadPitch &&
        result.headOffsetScore! >= 0 &&
        result.headOffsetScore! <= _eyeDetector.maxReliableHeadOffsetScore;
    final eyeReliable =
        headReliable &&
        result.hasEyeData &&
        _inRange(result.leftEyeOpen, 0, 1) &&
        _inRange(result.rightEyeOpen, 0, 1);
    final eye = _eyeDetector.evaluate(
      result: result,
      previousClosedFrameCount: 0,
    );
    final closed = eyeReliable && rawEyeClosed && eye.closedFrameCount > 0;
    final open = eyeReliable && !rawEyeClosed && eye.state == EyeState.open;
    final upright = poseReliable && open && pitch.abs() <= uprightPitch;
    if (_baselineNose == null) {
      if (upright) {
        _baselineSince ??= timestampMs;
        _baselineSamples.add(nose!);
        if (timestampMs - _baselineSince! >= baselineDurationMs) {
          final sorted = List<double>.of(_baselineSamples)..sort();
          _baselineNose = sorted[sorted.length ~/ 2];
          _baselineSamples.clear();
        }
      } else {
        _baselineSince = null;
        _baselineSamples.clear();
      }
    }
    final drop = nose != null && _baselineNose != null
        ? nose - _baselineNose!
        : null;
    final low =
        (headReliable && pitch.abs() >= _eyeDetector.readingPitchThreshold) ||
        (drop != null && drop >= lowHeadNoseDrop);
    final usablePostureScore =
        postureScore != null &&
            postureScore.isFinite &&
            postureScore >= 0 &&
            postureScore <= 100
        ? postureScore
        : null;
    final staticDeepPostureHigh =
        enableLongShortGate &&
        low &&
        poseReliable &&
        usablePostureScore != null &&
        usablePostureScore >= staticDeepPostureScoreThreshold;
    if (staticDeepPostureHigh) {
      _staticDeepPostureSince ??= timestampMs;
    } else {
      _staticDeepPostureSince = null;
    }
    final staticDeepPostureMs = _staticDeepPostureSince == null
        ? 0
        : timestampMs - _staticDeepPostureSince!;
    final staticDeepPostureConfirmed =
        staticDeepPostureMs >= staticDeepPostureDurationMs;
    final sample = _Sample(
      timestampMs,
      eyeReliable,
      poseReliable,
      closed,
      open,
      headReliable ? pitch : null,
      nose,
    );

    if (closed) {
      _closedSince ??= timestampMs;
      if (timestampMs - _closedSince! >= closureDurationMs &&
          nose != null &&
          _baselineNose != null &&
          nose - _baselineNose! <= 0.05 &&
          pitch.abs() <= uprightPitch) {
        _armedAt ??= timestampMs;
      }
    } else {
      _closedSince = null;
    }
    if (_armedAt != null && timestampMs - _armedAt! > closureExpiryMs) {
      _armedAt = null;
    }

    // A descent requires usable geometry at both ends. Missing landmarks never
    // create motion evidence, and stable low position alone cannot do so.
    if (nose != null) {
      for (final previous in _history.reversed) {
        if (timestampMs - previous.ms > descentDurationMs) break;
        if (previous.nose != null && nose - previous.nose! >= lowHeadNoseDrop) {
          _motionAt = timestampMs;
          break;
        }
      }
    }
    if (low &&
        drop != null &&
        drop >= lowHeadNoseDrop &&
        _armedAt != null &&
        _armedAt! < timestampMs &&
        _motionAt == timestampMs) {
      _eyeDescentAt = timestampMs;
      _armedAt = null;
    }
    _history.add(sample);
    final cutoff = timestampMs - windowMs;
    while (_history.length > 1 && _history[1].ms <= cutoff) {
      _history.removeAt(0);
    }

    final fastPriority =
        fastState.status == CompanionStatus.userMissing && !personMaskPresent
        ? 'user_missing'
        : strongPostureEvidence
        ? 'posture_down'
        : distracted
        ? 'distracted'
        : null;
    if (!enableLongShortGate && fastPriority != null) {
      _clearEpisode();
      _history
        ..clear()
        ..add(sample);
    } else if (low) {
      _lowSince ??= timestampMs;
      _recoverySince = null;
    } else if ((_slowState != SlowContextState.none || _sleepLatched) &&
        upright &&
        drop != null &&
        drop <= 0.05) {
      _recoverySince ??= timestampMs;
      if (timestampMs - _recoverySince! >= recoveryDurationMs) {
        _clearEpisode();
      }
    } else if (enableLongShortGate && !headReliable && !poseReliable) {
      _recoverySince = null;
      // Missing observations neither prove continued low-head posture nor
      // prove recovery. Keep the episode clock/history for later evidence.
      if (_slowState != SlowContextState.none && !_sleepLatched) {
        _slowState = SlowContextState.unknownLowHead;
      }
    } else {
      _recoverySince = null;
      _lowSince = null;
      // Lost data is uncertainty, not continuing evidence of sleep.
      if (_slowState != SlowContextState.none && !_sleepLatched) {
        _slowState = SlowContextState.unknownLowHead;
      }
    }

    var eyeMs = 0;
    var poseMs = 0;
    var openMs = 0;
    var currentClosedMs = 0;
    var maximumClosedMs = 0;
    for (var i = 0; i + 1 < _history.length; i++) {
      final previous = _history[i];
      final startMs = previous.ms > cutoff ? previous.ms : cutoff;
      final duration = _history[i + 1].ms - startMs;
      if (duration <= 0) continue;
      if (previous.eyeReliable) eyeMs += duration;
      if (previous.poseReliable) poseMs += duration;
      if (previous.open) openMs += duration;
      currentClosedMs = previous.closed ? currentClosedMs + duration : 0;
      maximumClosedMs = math.max(maximumClosedMs, currentClosedMs);
    }
    final eyeCoverage = eyeMs / windowMs;
    final poseCoverage = poseMs / windowMs;
    final recent = _history.where((sample) => sample.ms >= cutoff);
    final pitches = recent.where((s) => s.pitch != null).map((s) => s.pitch!);
    final noses = recent.where((s) => s.poseReliable).map((s) => s.nose!);
    final pitchRange = _range(pitches);
    final noseRange = _range(noses);
    final paired = _eyeDescentAt != null && _eyeDescentAt! >= cutoff;
    final evidenceEye =
        paired || _confirmedEyeEvidence || maximumClosedMs >= closureDurationMs;
    final evidenceMotion =
        _confirmedDrowsy || (_motionAt != null && _motionAt! >= cutoff);
    final mature =
        low && _lowSince != null && timestampMs - _lowSince! >= windowMs;
    final evidencePosture =
        mature &&
        poseReliable &&
        poseCoverage >= minimumCoverage &&
        drop != null &&
        drop >= lowHeadNoseDrop;
    final quality = _baselineNose == null
        ? 'calibrating'
        : eyeReliable &&
              poseReliable &&
              eyeCoverage >= minimumCoverage &&
              poseCoverage >= minimumCoverage
        ? 'good'
        : 'insufficient';
    final stableReadingEvidence =
        quality == 'good' &&
        open &&
        openMs / windowMs >= minimumCoverage &&
        !evidenceEye &&
        pitchRange != null &&
        pitchRange <= stablePitchRange &&
        noseRange != null &&
        noseRange <= stableNoseRange;
    final currentPostureTrigger = strongPostureEvidence && low;
    final currentFastSleepTrigger =
        fastState.status == CompanionStatus.sleeping &&
        !strongPostureEvidence &&
        low;
    final recentMotion = _motionAt != null && _motionAt! >= cutoff;
    final shortTrigger = currentPostureTrigger
        ? 'strong_posture'
        : staticDeepPostureConfirmed
        ? 'static_deep_posture'
        : paired
        ? 'eye_descent'
        : currentFastSleepTrigger
        ? 'fast_sleep'
        : recentMotion && evidenceEye
        ? 'head_drop_with_eye_evidence'
        : 'none';
    var longContext = upright
        ? LongHeadContext.upright
        : _lowSince != null && !low
        ? LongHeadContext.insufficientData
        : low && !mature
        ? LongHeadContext.observingLowHead
        : mature && poseCoverage < minimumCoverage
        ? LongHeadContext.insufficientData
        : mature &&
              evidencePosture &&
              poseCoverage >= minimumCoverage &&
              (currentPostureTrigger ||
                  staticDeepPostureConfirmed ||
                  currentFastSleepTrigger &&
                      eyeCoverage < minimumCoverage &&
                      !stableReadingEvidence)
        ? LongHeadContext.possibleDrowsy
        : mature &&
              pitchRange != null &&
              pitchRange <= stablePitchRange &&
              noseRange != null &&
              noseRange <= stableNoseRange
        ? LongHeadContext.stableLowHead
        : mature
        ? LongHeadContext.variableLowHead
        : LongHeadContext.insufficientData;

    if (enableLongShortGate) {
      // A strong posture trigger is already produced from a reliable current
      // pose by the posture detector. Requiring 80% pose coverage again here
      // prevents a mature low-head episode from latching when landmarks flicker
      // during real sleep. Keep the coverage requirement for the weaker fast
      // sleep signal, which does not carry the same posture confidence.
      final highConfidenceShortTrigger =
          currentPostureTrigger || staticDeepPostureConfirmed;
      final contextSupportedFastSleep =
          evidencePosture &&
          currentFastSleepTrigger &&
          eyeCoverage < minimumCoverage &&
          !stableReadingEvidence;
      if (!_sleepLatched &&
          mature &&
          (highConfidenceShortTrigger || contextSupportedFastSleep)) {
        _sleepLatched = true;
        _staticDeepPostureLatched =
            !currentPostureTrigger && staticDeepPostureConfirmed;
        _confirmedDrowsy = true;
        _confirmedEyeEvidence = _confirmedEyeEvidence || evidenceEye;
      }
      final reliableLowHeadRecovery =
          _sleepLatched &&
          low &&
          !strongPostureEvidence &&
          eyeCoverage >= minimumCoverage &&
          poseCoverage >= minimumCoverage &&
          (!_staticDeepPostureLatched || !staticDeepPostureHigh);
      if (reliableLowHeadRecovery) {
        _lowHeadRecoverySince ??= timestampMs;
        if (timestampMs - _lowHeadRecoverySince! >= recoveryDurationMs) {
          _clearEpisode();
          longContext = LongHeadContext.stableLowHead;
        }
      } else {
        _lowHeadRecoverySince = null;
      }
      if (_sleepLatched) {
        _slowState = SlowContextState.drowsyLike;
        longContext = LongHeadContext.possibleDrowsy;
      } else if (mature) {
        _slowState = stableReadingEvidence
            ? SlowContextState.readingLike
            : SlowContextState.unknownLowHead;
      }
    } else if (fastPriority == null && mature) {
      if (evidencePosture &&
          evidenceMotion &&
          (paired ||
              _confirmedDrowsy &&
                  !(open && openMs / windowMs >= minimumCoverage) ||
              noseRange != null &&
                  noseRange >= lowHeadNoseDrop &&
                  !(open && openMs / windowMs >= minimumCoverage))) {
        _slowState = SlowContextState.drowsyLike;
        _confirmedDrowsy = true;
        _confirmedEyeEvidence = _confirmedEyeEvidence || evidenceEye;
      } else if (stableReadingEvidence) {
        _slowState = SlowContextState.readingLike;
      } else {
        _slowState = SlowContextState.unknownLowHead;
      }
    }

    if (enableLongShortGate && _sleepLatched) {
      if (!result.hasFace && !result.hasPose && !personMaskPresent) {
        _fullyMissingWhileLatchedSince ??= timestampMs;
      } else {
        _fullyMissingWhileLatchedSince = null;
      }
      final sideExit = disappearance?.sideExit ?? false;
      final missingExpired =
          _fullyMissingWhileLatchedSince != null &&
          timestampMs - _fullyMissingWhileLatchedSince! >= windowMs;
      final confirmedAway =
          !personMaskPresent &&
          disappearance?.state == DisappearanceState.away &&
          (sideExit || missingExpired);
      final unavailableWithoutPresence =
          !personMaskPresent &&
          disappearance == null &&
          fastState.status == CompanionStatus.userMissing;
      if (confirmedAway || unavailableWithoutPresence) {
        _clearEpisode();
      }
    }

    final finalState = enableLongShortGate && strongPostureEvidence
        ? 'posture_down'
        : enableLongShortGate && _sleepLatched
        ? 'drowsy_like'
        : presenceOverride ??
              fastPriority ??
              (_slowState != SlowContextState.none
                  ? _slowState.csvValue
                  : low
                  ? 'normal'
                  : enableHeadScoreSum &&
                        fastState.status == CompanionStatus.distracted
                  ? 'normal'
                  : fastState.status.name);
    return DualTrackContextResult(
      lowHeadCandidate: low,
      slowState: _slowState,
      slowWindowMs: _lowSince == null
          ? 0
          : math.min(windowMs, timestampMs - _lowSince!),
      evidenceEye: evidenceEye,
      evidenceMotion: evidenceMotion,
      evidencePosture: evidencePosture,
      dataQuality: quality,
      finalState: finalState,
      eyeCoverage: eyeCoverage,
      poseCoverage: poseCoverage,
      closedDurationMs: maximumClosedMs,
      noseDrop: drop,
      pitchRange: pitchRange,
      noseRange: noseRange,
      motionEvidenceAtMs: _motionAt,
      eyeDescentAtMs: _eyeDescentAt,
      drowsyConfirmed: _confirmedDrowsy,
      longContext: longContext,
      shortTrigger: shortTrigger,
      sleepLatched: _sleepLatched,
      postureScore: usablePostureScore,
      staticDeepPostureMs: staticDeepPostureMs,
      disappearance: disappearance,
      headScore: headScore,
    );
  }

  static bool hasReliablePoseGeometry(VisionResult result) {
    final width = result.imageWidth;
    final height = result.imageHeight;
    if (!result.hasPose ||
        width == null ||
        height == null ||
        !width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0) {
      return false;
    }
    return _inRange(result.poseNoseVisibility, minimumVisibility, 1) &&
        _inRange(result.leftShoulderVisibility, minimumVisibility, 1) &&
        _inRange(result.rightShoulderVisibility, minimumVisibility, 1) &&
        _inRange(result.poseNoseX, 0, width) &&
        _inRange(result.poseNoseY, 0, height) &&
        _inRange(result.leftShoulderX, 0, width) &&
        _inRange(result.rightShoulderX, 0, width) &&
        _inRange(result.leftShoulderY, 0, height) &&
        _inRange(result.rightShoulderY, 0, height) &&
        (result.leftShoulderX! - result.rightShoulderX!).abs() / height >= 0.05;
  }

  static bool _inRange(double? value, double low, double high) =>
      value != null && value.isFinite && value >= low && value <= high;

  static double? _range(Iterable<double> values) {
    if (values.isEmpty) return null;
    return values.reduce(math.max) - values.reduce(math.min);
  }

  void _clearEpisode() {
    _lowSince = null;
    _recoverySince = null;
    _closedSince = null;
    _armedAt = null;
    _eyeDescentAt = null;
    _motionAt = null;
    _fullyMissingWhileLatchedSince = null;
    _lowHeadRecoverySince = null;
    _staticDeepPostureSince = null;
    _confirmedDrowsy = false;
    _confirmedEyeEvidence = false;
    _sleepLatched = false;
    _staticDeepPostureLatched = false;
    _slowState = SlowContextState.none;
  }

  void reset() {
    _clearEpisode();
    _history.clear();
    _baselineSamples.clear();
    _baselineSince = null;
    _baselineNose = null;
    _lastTimestamp = null;
    _disappearance.reset();
    _headScoreDetector.reset();
    _headDistractedFrames = 0;
  }
}

class _Sample {
  const _Sample(
    this.ms,
    this.eyeReliable,
    this.poseReliable,
    this.closed,
    this.open,
    this.pitch,
    this.nose,
  );

  final int ms;
  final bool eyeReliable;
  final bool poseReliable;
  final bool closed;
  final bool open;
  final double? pitch;
  final double? nose;
}
