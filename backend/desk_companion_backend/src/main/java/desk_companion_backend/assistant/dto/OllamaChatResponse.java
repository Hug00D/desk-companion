package desk_companion_backend.assistant.dto;

public record OllamaChatResponse(
        String model,
        AssistantMessage message,
        Boolean done
) {
}
