package desk_companion_backend.user.dto;

import java.time.OffsetDateTime;
import java.util.UUID;

public record ProfileResponse(
        UUID id, //same with user id
        String displayName,
        String avatarUrl,
        OffsetDateTime createdAt,
        OffsetDateTime updatedAt
) {}