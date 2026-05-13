package desk_companion_backend.auth.dto;

public record AccountRecoveryResponse(
        String message,
        String recoveryToken
) {}
