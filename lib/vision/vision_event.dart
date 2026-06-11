import 'companion_state_evaluator.dart';
import 'eye_state_detector.dart';
import 'presence_detector.dart';
import 'vision_result.dart';

enum VisionEventType {
  normal,
  partialUserDetected,
  userAway,
  userReturned,
  attentionWarning,
  fatigueDetected,
}

extension VisionEventTypeStorage on VisionEventType {
  String get storageValue {
    switch (this) {
      case VisionEventType.normal:
        return 'vision.normal';
      case VisionEventType.partialUserDetected:
        return 'vision.partial_user_detected';
      case VisionEventType.userAway:
        return 'vision.user_away';
      case VisionEventType.userReturned:
        return 'vision.user_returned';
      case VisionEventType.attentionWarning:
        return 'vision.attention_warning';
      case VisionEventType.fatigueDetected:
        return 'vision.fatigue_detected';
    }
  }
}

enum VisionEventSeverity { info, attention, warning }

extension VisionEventSeverityStorage on VisionEventSeverity {
  String get storageValue {
    switch (this) {
      case VisionEventSeverity.info:
        return 'info';
      case VisionEventSeverity.attention:
        return 'attention';
      case VisionEventSeverity.warning:
        return 'warning';
    }
  }
}

class VisionEvent {
  const VisionEvent({
    required this.type,
    required this.severity,
    required this.timestamp,
    required this.status,
    required this.eyeState,
    required this.presenceState,
    required this.poseStateName,
    required this.result,
    this.detectedObject,
    this.confidenceScore,
    this.actionTriggered,
  });

  final VisionEventType type;
  final VisionEventSeverity severity;
  final DateTime timestamp;
  final CompanionStatus status;
  final EyeState eyeState;
  final PresenceState presenceState;
  final String poseStateName;
  final VisionResult result;
  final String? detectedObject;
  final double? confidenceScore;
  final String? actionTriggered;

  bool get shouldPersist => type != VisionEventType.normal;

  factory VisionEvent.fromAnalysis(
    CompanionAnalysis analysis, {
    DateTime? timestamp,
    VisionEventType? typeOverride,
    String? actionTriggered,
  }) {
    final eventType = typeOverride ?? _typeFromAnalysis(analysis);
    return VisionEvent(
      type: eventType,
      severity: _severityFor(eventType),
      timestamp: timestamp ?? DateTime.now(),
      status: analysis.status,
      eyeState: analysis.eyeResult.state,
      presenceState: analysis.presenceState,
      poseStateName: analysis.poseState.name,
      result: analysis.visionResult,
      detectedObject: _detectedObjectFor(eventType),
      confidenceScore: _confidenceFromRaw(analysis.visionResult),
      actionTriggered: actionTriggered,
    );
  }

  Map<String, dynamic> toBehaviorEventPayload() {
    return {
      'ts': timestamp.toUtc().toIso8601String(),
      'eventType': type.storageValue,
      'detectedObject': detectedObject,
      'confidenceScore': confidenceScore,
      'signals': toSignalsJson(),
      'actionTriggered': actionTriggered,
    };
  }

  Map<String, dynamic> toSignalsJson() {
    return {
      'source': 'vision',
      'severity': severity.storageValue,
      'status': status.name,
      'eyeState': eyeState.name,
      'presenceState': presenceState.name,
      'poseState': poseStateName,
      'hasFace': result.hasFace,
      'hasPose': result.hasPose,
      'leftEye': result.leftEyeOpen,
      'rightEye': result.rightEyeOpen,
      'shoulderWidth': result.shoulderWidth,
      'raw': _stringKeyedRaw(result.raw),
    };
  }

  static VisionEventType _typeFromAnalysis(CompanionAnalysis analysis) {
    if (analysis.status == CompanionStatus.fatigue) {
      return VisionEventType.fatigueDetected;
    }
    if (analysis.status == CompanionStatus.attention) {
      return VisionEventType.attentionWarning;
    }
    if (analysis.presenceState == PresenceState.away) {
      return VisionEventType.userAway;
    }
    if (analysis.presenceState == PresenceState.faceOnly ||
        analysis.presenceState == PresenceState.bodyOnly) {
      return VisionEventType.partialUserDetected;
    }
    return VisionEventType.normal;
  }

  static VisionEventSeverity _severityFor(VisionEventType type) {
    switch (type) {
      case VisionEventType.fatigueDetected:
      case VisionEventType.userAway:
      case VisionEventType.userReturned:
        return VisionEventSeverity.warning;
      case VisionEventType.attentionWarning:
      case VisionEventType.partialUserDetected:
        return VisionEventSeverity.attention;
      case VisionEventType.normal:
        return VisionEventSeverity.info;
    }
  }

  static String? _detectedObjectFor(VisionEventType type) {
    switch (type) {
      case VisionEventType.fatigueDetected:
      case VisionEventType.attentionWarning:
        return 'eyes';
      case VisionEventType.userAway:
      case VisionEventType.partialUserDetected:
      case VisionEventType.userReturned:
        return 'user';
      case VisionEventType.normal:
        return null;
    }
  }

  static double? _confidenceFromRaw(VisionResult result) {
    final faceConfidence = _toDouble(result.raw['faceConfidence']);
    final poseConfidence = _toDouble(result.raw['poseConfidence']);
    if (faceConfidence != null && poseConfidence != null) {
      return (faceConfidence + poseConfidence) / 2;
    }
    return faceConfidence ?? poseConfidence;
  }

  static Map<String, dynamic> _stringKeyedRaw(Map<dynamic, dynamic> raw) {
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }

  static double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return null;
  }
}
