package desk_companion_backend.focus.controller;

import desk_companion_backend.focus.dto.BehaviorEventBatchRequest;
import desk_companion_backend.focus.dto.BehaviorEventBatchResponse;
import desk_companion_backend.focus.dto.FocusRoundRequest;
import desk_companion_backend.focus.dto.FocusRoundResponse;
import desk_companion_backend.focus.dto.FocusSessionRequest;
import desk_companion_backend.focus.dto.FocusSessionResponse;
import desk_companion_backend.focus.service.BehaviorEventService;
import desk_companion_backend.focus.service.FocusSessionService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

@RestController
@RequestMapping("/api/v1/users/{userId}/focus-sessions")
public class FocusSessionController {

    private final FocusSessionService focusSessionService;
    private final BehaviorEventService behaviorEventService;

    public FocusSessionController(
            FocusSessionService focusSessionService,
            BehaviorEventService behaviorEventService
    ) {
        this.focusSessionService = focusSessionService;
        this.behaviorEventService = behaviorEventService;
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public FocusSessionResponse createSession(
            @PathVariable UUID userId,
            @Valid @RequestBody FocusSessionRequest request
    ) {
        return focusSessionService.createSession(userId, request);
    }

    @PatchMapping("/{sessionId}")
    public FocusSessionResponse updateSession(
            @PathVariable UUID userId,
            @PathVariable UUID sessionId,
            @Valid @RequestBody FocusSessionRequest request
    ) {
        return focusSessionService.updateSession(userId, sessionId, request);
    }

    @PostMapping("/{sessionId}/rounds")
    @ResponseStatus(HttpStatus.CREATED)
    public FocusRoundResponse createRound(
            @PathVariable UUID userId,
            @PathVariable UUID sessionId,
            @Valid @RequestBody FocusRoundRequest request
    ) {
        return focusSessionService.createRound(userId, sessionId, request);
    }

    @PatchMapping("/{sessionId}/rounds/{roundId}")
    public FocusRoundResponse updateRound(
            @PathVariable UUID userId,
            @PathVariable UUID sessionId,
            @PathVariable UUID roundId,
            @Valid @RequestBody FocusRoundRequest request
    ) {
        return focusSessionService.updateRound(userId, sessionId, roundId, request);
    }

    @PostMapping("/{sessionId}/events/batch")
    public BehaviorEventBatchResponse saveEvents(
            @PathVariable UUID userId,
            @PathVariable UUID sessionId,
            @Valid @RequestBody BehaviorEventBatchRequest request
    ) {
        return behaviorEventService.saveBatch(userId, sessionId, request);
    }
}
