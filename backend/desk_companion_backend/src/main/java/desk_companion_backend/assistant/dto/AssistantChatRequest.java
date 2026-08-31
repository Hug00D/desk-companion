package desk_companion_backend.assistant.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.util.List;
import java.util.Map;

public record AssistantChatRequest(
        @NotBlank(message = "message is required")
        @Size(max = 2000, message = "message cannot exceed 2000 characters")
        String message,

        @Valid
        @Size(max = 20, message = "history cannot exceed 20 messages")
        List<AssistantMessage> history,

        Map<String, Object> context
) {
}
