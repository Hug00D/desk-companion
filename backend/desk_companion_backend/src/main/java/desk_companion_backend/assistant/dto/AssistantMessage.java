package desk_companion_backend.assistant.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

public record AssistantMessage(
        @NotBlank(message = "role is required")
        @Pattern(regexp = "system|user|assistant", message = "role must be system, user, or assistant")
        String role,

        @NotBlank(message = "content is required")
        @Size(max = 4000, message = "content cannot exceed 4000 characters")
        String content
) {
}
