import '../ai/assistant_reply.dart';

/// Determines whether a backend assistant reply should be played aloud.
///
/// This policy is intentionally limited to AI answer audio. Wake
/// acknowledgement sounds and proactive vision reminders have separate
/// controls.
class AssistantVoiceReplyPolicy {
  const AssistantVoiceReplyPolicy();

  bool shouldPlay({
    required bool voiceReplyEnabled,
    required bool dynamicVoiceEnabled,
    required AssistantMode mode,
    required bool usedFallback,
    required AssistantAudio? audio,
  }) {
    return voiceReplyEnabled &&
        dynamicVoiceEnabled &&
        mode == AssistantMode.chat &&
        !usedFallback &&
        audio != null &&
        audio.bytes.isNotEmpty;
  }
}
