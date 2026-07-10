package desk_companion_backend.focus.service.impl;

import desk_companion_backend.common.exception.FocusRoundNotFoundException;
import desk_companion_backend.common.exception.FocusSessionNotFoundException;
import desk_companion_backend.focus.dto.BehaviorEventBatchRequest;
import desk_companion_backend.focus.dto.BehaviorEventBatchResponse;
import desk_companion_backend.focus.dto.BehaviorEventRequest;
import desk_companion_backend.focus.dto.BehaviorEventResponse;
import desk_companion_backend.focus.entity.BehaviorEvent;
import desk_companion_backend.focus.entity.FocusRound;
import desk_companion_backend.focus.entity.FocusSession;
import desk_companion_backend.focus.repository.BehaviorEventRepository;
import desk_companion_backend.focus.repository.FocusRoundRepository;
import desk_companion_backend.focus.repository.FocusSessionRepository;
import desk_companion_backend.focus.service.BehaviorEventService;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

@Service
@Transactional(readOnly = true)
public class BehaviorEventServiceImpl implements BehaviorEventService {

    private final FocusSessionRepository focusSessionRepository;
    private final FocusRoundRepository focusRoundRepository;
    private final BehaviorEventRepository behaviorEventRepository;

    public BehaviorEventServiceImpl(
            FocusSessionRepository focusSessionRepository,
            FocusRoundRepository focusRoundRepository,
            BehaviorEventRepository behaviorEventRepository
    ) {
        this.focusSessionRepository = focusSessionRepository;
        this.focusRoundRepository = focusRoundRepository;
        this.behaviorEventRepository = behaviorEventRepository;
    }

    @Override
    @Transactional
    public BehaviorEventBatchResponse saveBatch(UUID userId, UUID sessionId, BehaviorEventBatchRequest request) {
        FocusSession session = focusSessionRepository.findByIdAndUserId(sessionId, userId)
                .orElseThrow(FocusSessionNotFoundException::new);

        int skipped = 0;
        var saved = new ArrayList<BehaviorEventResponse>();

        for (BehaviorEventRequest item : request.events()) {
            if (item.clientEventId() != null
                    && behaviorEventRepository.findByUserIdAndClientEventId(userId, item.clientEventId()).isPresent()) {
                skipped += 1;
                continue;
            }

            BehaviorEvent event = new BehaviorEvent();
            event.setUser(session.getUser());
            event.setSession(session);
            event.setRound(resolveRound(userId, sessionId, item.roundId()));
            event.setClientEventId(item.clientEventId());
            event.setRelatedEventId(item.relatedEventId());
            event.setTs(item.ts() == null ? OffsetDateTime.now() : item.ts());
            event.setSource(trimOrDefault(item.source(), "vision"));
            event.setEventType(item.eventType());
            event.setSeverity(trimOrDefault(item.severity(), "info"));
            event.setPhase(trimOrDefault(item.phase(), "point"));
            event.setDurationMs(item.durationMs());
            event.setDetectedObject(trimOrNull(item.detectedObject()));
            event.setConfidenceScore(item.confidenceScore());
            event.setSignals(copyMap(item.signals()));
            event.setActionTriggered(trimOrNull(item.actionTriggered()));
            event.setOutcome(trimOrDefault(item.outcome(), "observed"));
            event.setDebugSnapshotPath(trimOrNull(item.debugSnapshotPath()));
            event.setSchemaVersion(item.schemaVersion() == null ? 1 : item.schemaVersion());

            saved.add(toResponse(behaviorEventRepository.save(event)));
        }

        return new BehaviorEventBatchResponse(saved.size(), skipped, saved);
    }

    private FocusRound resolveRound(UUID userId, UUID sessionId, UUID roundId) {
        if (roundId == null) {
            return null;
        }
        return focusRoundRepository.findByIdAndUserIdAndSessionId(roundId, userId, sessionId)
                .orElseThrow(FocusRoundNotFoundException::new);
    }

    private BehaviorEventResponse toResponse(BehaviorEvent event) {
        return new BehaviorEventResponse(
                event.getId(),
                event.getUser().getId(),
                event.getSession() == null ? null : event.getSession().getId(),
                event.getRound() == null ? null : event.getRound().getId(),
                event.getClientEventId(),
                event.getRelatedEventId(),
                event.getSource(),
                event.getEventType(),
                event.getTs(),
                event.getSeverity(),
                event.getPhase(),
                event.getDurationMs(),
                event.getConfidenceScore(),
                event.getDetectedObject(),
                event.getActionTriggered(),
                event.getOutcome(),
                event.getDebugSnapshotPath(),
                event.getSignals(),
                event.getSchemaVersion()
        );
    }

    private static String trimOrDefault(String value, String fallback) {
        if (value == null || value.isBlank()) {
            return fallback;
        }
        return value.trim();
    }

    private static String trimOrNull(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        return value.trim();
    }

    private static Map<String, Object> copyMap(Map<String, Object> value) {
        return value == null ? new HashMap<>() : new HashMap<>(value);
    }
}
