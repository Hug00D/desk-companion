package desk_companion_backend.assistant.dto;

import java.util.List;
import java.util.Map;

public record OllamaChatRequest(
        String model,
        List<AssistantMessage> messages,
        Boolean stream,
        Map<String, Object> options,
        Object format
) {
}
