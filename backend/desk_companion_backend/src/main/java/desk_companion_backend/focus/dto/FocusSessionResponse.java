package desk_companion_backend.focus.dto;

import java.time.OffsetDateTime;
import java.util.Map;
import java.util.UUID;

public record FocusSessionResponse(
        UUID sessionId,
        UUID userId,
        UUID clientSessionId,
        OffsetDateTime startAt,
        OffsetDateTime endAt,
        String status,
        String endReason,
        String mode,
        String timezone,
        Integer targetSeconds,
        int monitoredSeconds,
        int focusSeconds,
        int distractedSeconds,
        int attentionSeconds,
        int fatigueSeconds,
        int drowsySeconds,
        int postureDownSeconds,
        int awaySeconds,
        int pausedSeconds,
        int breakSeconds,
        int reminderCount,
        Map<String, Object> summary,
        Map<String, Object> config,
        int revision,
        int schemaVersion
) {
}
