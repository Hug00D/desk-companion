package desk_companion_backend.user.dto;

public record AccountStatusCheckResponse(
        String accountStatus,
        boolean loginAllowed,
        String message
) {}