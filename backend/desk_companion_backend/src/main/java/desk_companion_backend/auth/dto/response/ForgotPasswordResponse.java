package desk_companion_backend.auth.dto;

public record ForgotPasswordResponse(
        String message,
        String resetToken
) {}
