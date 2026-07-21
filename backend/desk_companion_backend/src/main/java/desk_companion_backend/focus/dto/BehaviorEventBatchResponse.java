package desk_companion_backend.focus.dto;

import java.util.List;

public record BehaviorEventBatchResponse(
        int savedCount,
        int skippedDuplicateCount,
        List<BehaviorEventResponse> events
) {
}
