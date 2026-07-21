package desk_companion_backend.focus.service;

import desk_companion_backend.focus.dto.BehaviorEventBatchRequest;
import desk_companion_backend.focus.dto.BehaviorEventBatchResponse;

import java.util.UUID;

public interface BehaviorEventService {

    BehaviorEventBatchResponse saveBatch(UUID userId, UUID sessionId, BehaviorEventBatchRequest request);
}
