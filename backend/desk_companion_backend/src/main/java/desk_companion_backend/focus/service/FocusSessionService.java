package desk_companion_backend.focus.service;

import desk_companion_backend.focus.dto.FocusRoundRequest;
import desk_companion_backend.focus.dto.FocusRoundResponse;
import desk_companion_backend.focus.dto.FocusSessionRequest;
import desk_companion_backend.focus.dto.FocusSessionResponse;

import java.util.UUID;

public interface FocusSessionService {

    FocusSessionResponse createSession(UUID userId, FocusSessionRequest request);

    FocusSessionResponse updateSession(UUID userId, UUID sessionId, FocusSessionRequest request);

    FocusRoundResponse createRound(UUID userId, UUID sessionId, FocusRoundRequest request);

    FocusRoundResponse updateRound(UUID userId, UUID sessionId, UUID roundId, FocusRoundRequest request);
}
