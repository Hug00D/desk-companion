package desk_companion_backend.auth.dto;

import jakarta.validation.constraints.NotBlank;

public record ConfirmAccountRecoveryRequest(
        @NotBlank(message = "Recovery token is required")
        String token
) {}
