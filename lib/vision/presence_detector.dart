import 'vision_result.dart';

enum PresenceState { present, faceOnly, bodyOnly, away }

class PresenceDetector {
  const PresenceDetector();

  PresenceState evaluate(VisionResult result) {
    if (result.hasFace && result.hasPose) return PresenceState.present;
    if (result.hasFace) return PresenceState.faceOnly;
    if (result.hasPose) return PresenceState.bodyOnly;
    return PresenceState.away;
  }
}
