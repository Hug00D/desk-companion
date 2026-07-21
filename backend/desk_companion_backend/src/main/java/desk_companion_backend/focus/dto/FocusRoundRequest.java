package desk_companion_backend.focus.dto;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.time.OffsetDateTime;
import java.util.UUID;

public record FocusRoundRequest(
        UUID clientRoundId,
        UUID sessionId,

        @Min(value = 1, message = "roundNumber must be positive")
        int roundNumber,

        @NotBlank(message = "roundType is required")
        String roundType,

        @NotBlank(message = "status is required")
        String status,

        @Min(value = 1, message = "targetSeconds must be positive")
        int targetSeconds,

        @Min(value = 0, message = "actualSeconds cannot be negative")
        Integer actualSeconds,

        @Min(value = 0, message = "pausedSeconds cannot be negative")
        Integer pausedSeconds,

        @NotNull(message = "startAt is required")
        OffsetDateTime startAt,

        OffsetDateTime endAt,
        String endReason,

        @Min(value = 1, message = "schemaVersion must be positive")
        Integer schemaVersion
) {
}
