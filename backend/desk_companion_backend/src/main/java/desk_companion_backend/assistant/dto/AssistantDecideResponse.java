package desk_companion_backend.assistant.dto;

import java.util.Map;

public record AssistantDecideResponse(
        String mode,
        String intent,
        Double confidence,
        Boolean needsConfirmation,
        String confirmationText,
        String chatReply,
        Map<String, Object> parameters,
        String model
) {
}
