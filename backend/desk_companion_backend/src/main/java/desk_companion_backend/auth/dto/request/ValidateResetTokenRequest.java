package desk_companion_backend.auth.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;

public record ValidateResetTokenRequest(
        @Email(message = "Email format is invalid")
        String email,

        @NotBlank(message = "Reset token is required")
        String token
) {}
