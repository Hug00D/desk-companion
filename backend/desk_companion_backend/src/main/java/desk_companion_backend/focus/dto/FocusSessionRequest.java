package desk_companion_backend.focus.dto;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

import java.time.OffsetDateTime;
import java.util.Map;
import java.util.UUID;

public record FocusSessionRequest(
        UUID clientSessionId,

        @NotNull(message = "startAt is required")
        OffsetDateTime startAt,

        OffsetDateTime endAt,

        @NotBlank(message = "status is required")
        String status,

        String endReason,
        String mode,

        @NotBlank(message = "timezone is required")
        String timezone,

        @Min(value = 1, message = "targetSeconds must be positive")
        Integer targetSeconds,

        @Min(value = 0, message = "monitoredSeconds cannot be negative")
        Integer monitoredSeconds,

        @Min(value = 0, message = "focusSeconds cannot be negative")
        Integer focusSeconds,

        @Min(value = 0, message = "distractedSeconds cannot be negative")
        Integer distractedSeconds,

        @Min(value = 0, message = "attentionSeconds cannot be negative")
        Integer attentionSeconds,

        @Min(value = 0, message = "fatigueSeconds cannot be negative")
        Integer fatigueSeconds,

        @Min(value = 0, message = "drowsySeconds cannot be negative")
        Integer drowsySeconds,

        @Min(value = 0, message = "postureDownSeconds cannot be negative")
        Integer postureDownSeconds,

        @Min(value = 0, message = "awaySeconds cannot be negative")
        Integer awaySeconds,

        @Min(value = 0, message = "pausedSeconds cannot be negative")
        Integer pausedSeconds,

        @Min(value = 0, message = "breakSeconds cannot be negative")
        Integer breakSeconds,

        @Min(value = 0, message = "reminderCount cannot be negative")
        Integer reminderCount,

        Map<String, Object> summary,
        Map<String, Object> config,

        @Min(value = 0, message = "revision cannot be negative")
        Integer revision,

        @Min(value = 1, message = "schemaVersion must be positive")
        Integer schemaVersion
) {
}
