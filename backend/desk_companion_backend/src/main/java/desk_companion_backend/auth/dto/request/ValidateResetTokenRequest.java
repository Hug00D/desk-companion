package desk_companion_backend.auth.dto;

import jakarta.validation.constraints.NotBlank;

public record ValidateResetTokenRequest(
        @NotBlank(message = "Reset token is required")
        String token
) {}
