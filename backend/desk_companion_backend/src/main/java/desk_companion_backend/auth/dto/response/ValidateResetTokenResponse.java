package desk_companion_backend.auth.dto;

public record ValidateResetTokenResponse(
        boolean valid,
        String message
) {}
