package desk_companion_backend.auth.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;

public record RequestAccountRecoveryRequest(
        @NotBlank(message = "Email is required")
        @Email(message = "Email format is invalid")
        String email
) {}
