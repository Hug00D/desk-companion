package desk_companion_backend.focus.dto;

import java.time.OffsetDateTime;
import java.util.Map;
import java.util.UUID;

public record BehaviorEventResponse(
        Long id,
        UUID userId,
        UUID sessionId,
        UUID roundId,
        UUID clientEventId,
        Long relatedEventId,
        String source,
        String eventType,
        OffsetDateTime ts,
        String severity,
        String phase,
        Integer durationMs,
        Double confidenceScore,
        String detectedObject,
        String actionTriggered,
        String outcome,
        String debugSnapshotPath,
        Map<String, Object> signals,
        int schemaVersion
) {
}
