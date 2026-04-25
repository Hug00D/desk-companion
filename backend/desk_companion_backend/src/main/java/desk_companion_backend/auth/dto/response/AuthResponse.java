package desk_companion_backend.auth.dto;

import java.util.UUID;

public record AuthResponse(
        UUID userId,
        String email,
        String message
) {}