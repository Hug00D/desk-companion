package desk_companion_backend.focus.dto;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.time.OffsetDateTime;
import java.util.Map;
import java.util.UUID;

public record BehaviorEventRequest(
        UUID clientEventId,
        UUID sessionId,
        UUID roundId,
        Long relatedEventId,

        @NotBlank(message = "source is required")
        String source,

        @NotBlank(message = "eventType is required")
        String eventType,

        @NotNull(message = "ts is required")
        OffsetDateTime ts,

        String severity,
        String phase,

        @Min(value = 0, message = "durationMs cannot be negative")
        Integer durationMs,

        Double confidenceScore,
        String detectedObject,
        String actionTriggered,
        String outcome,
        String debugSnapshotPath,
        Map<String, Object> signals,

        @Min(value = 1, message = "schemaVersion must be positive")
        Integer schemaVersion
) {
}
