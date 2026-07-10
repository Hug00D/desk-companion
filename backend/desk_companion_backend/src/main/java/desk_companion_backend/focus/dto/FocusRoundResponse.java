package desk_companion_backend.focus.dto;

import java.time.OffsetDateTime;
import java.util.UUID;

public record FocusRoundResponse(
        UUID roundId,
        UUID userId,
        UUID sessionId,
        UUID clientRoundId,
        int roundNumber,
        String roundType,
        String status,
        int targetSeconds,
        int actualSeconds,
        int pausedSeconds,
        OffsetDateTime startAt,
        OffsetDateTime endAt,
        String endReason,
        int schemaVersion
) {
}
