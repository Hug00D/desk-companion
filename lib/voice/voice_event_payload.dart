import '../events/companion_event.dart';
import 'voice_command.dart';
import 'voice_result.dart';

class VoiceEventPayload {
  const VoiceEventPayload._();

  static CompanionEvent fromRecognition({
    required String studySessionId,
    required VoiceRecognitionResult recognition,
    VoiceCommand? command,
    String? roundId,
    String? actionTriggered,
    CompanionEventOutcome outcome = CompanionEventOutcome.observed,
    bool includeTranscript = false,
  }) {
    final isError = recognition.hasError;
    final eventType = isError
        ? 'voice.recognition_error'
        : 'voice.command_recognized';

    return CompanionEvent.create(
      sessionId: studySessionId,
      roundId: roundId,
      source: CompanionEventSource.voice,
      eventType: eventType,
      occurredAt: DateTime.fromMillisecondsSinceEpoch(recognition.timestampMs),
      severity: isError
          ? CompanionEventSeverity.attention
          : CompanionEventSeverity.info,
      confidenceScore: command?.confidence ?? recognition.bestConfidence,
      actionTriggered: actionTriggered,
      outcome: outcome,
      signals: <String, dynamic>{
        'recognition': recognition.toJson(includeTranscript: includeTranscript),
        if (command != null)
          'command': command.toJson(includeSourceText: includeTranscript),
      },
    );
  }
}
