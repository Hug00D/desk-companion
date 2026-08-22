package desk_companion_backend.assistant.dto;

public record AssistantChatResponse(
        String mode,
        String message,
        String intent,
        String action,
        String model,
        AssistantAudioResponse audio
) {
}
