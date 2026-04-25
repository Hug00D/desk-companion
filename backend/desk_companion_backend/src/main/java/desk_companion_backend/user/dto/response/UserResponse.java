package desk_companion_backend.user.dto;

import java.time.OffsetDateTime;
import java.util.UUID;

public record UserResponse(
        UUID id,
        String email,
        String authProvider,
        boolean emailVerified,
        String accountStatus,
        OffsetDateTime createdAt,
        OffsetDateTime updatedAt,
        ProfileResponse profile
) {}