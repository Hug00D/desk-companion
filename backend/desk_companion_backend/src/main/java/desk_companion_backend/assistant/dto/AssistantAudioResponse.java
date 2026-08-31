package desk_companion_backend.assistant.dto;

public record AssistantAudioResponse(
        String requestId,
        String contentType,
        String base64,
        Long durationMs
) {
}
