package desk_companion_backend.focus.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotEmpty;

import java.util.List;

public record BehaviorEventBatchRequest(
        @NotEmpty(message = "events cannot be empty")
        List<@Valid BehaviorEventRequest> events
) {
}
