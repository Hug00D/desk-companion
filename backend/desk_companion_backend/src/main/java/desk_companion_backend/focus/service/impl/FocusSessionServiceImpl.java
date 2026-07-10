package desk_companion_backend.focus.service.impl;

import desk_companion_backend.common.exception.FocusRoundNotFoundException;
import desk_companion_backend.common.exception.FocusSessionNotFoundException;
import desk_companion_backend.common.exception.UserNotFoundException;
import desk_companion_backend.focus.dto.FocusRoundRequest;
import desk_companion_backend.focus.dto.FocusRoundResponse;
import desk_companion_backend.focus.dto.FocusSessionRequest;
import desk_companion_backend.focus.dto.FocusSessionResponse;
import desk_companion_backend.focus.entity.FocusRound;
import desk_companion_backend.focus.entity.FocusSession;
import desk_companion_backend.focus.repository.FocusRoundRepository;
import desk_companion_backend.focus.repository.FocusSessionRepository;
import desk_companion_backend.focus.service.FocusSessionService;
import desk_companion_backend.user.entity.User;
import desk_companion_backend.user.repository.UserRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

@Service
@Transactional(readOnly = true)
public class FocusSessionServiceImpl implements FocusSessionService {

    private final UserRepository userRepository;
    private final FocusSessionRepository focusSessionRepository;
    private final FocusRoundRepository focusRoundRepository;

    public FocusSessionServiceImpl(
            UserRepository userRepository,
            FocusSessionRepository focusSessionRepository,
            FocusRoundRepository focusRoundRepository
    ) {
        this.userRepository = userRepository;
        this.focusSessionRepository = focusSessionRepository;
        this.focusRoundRepository = focusRoundRepository;
    }

    @Override
    @Transactional
    public FocusSessionResponse createSession(UUID userId, FocusSessionRequest request) {
        User user = getUser(userId);

        if (request.clientSessionId() != null) {
            var existing = focusSessionRepository.findByUserIdAndClientSessionId(userId, request.clientSessionId());
            if (existing.isPresent()) {
                return toSessionResponse(existing.get());
            }
        }

        FocusSession session = new FocusSession();
        session.setUser(user);
        applySessionRequest(session, request, true);
        return toSessionResponse(focusSessionRepository.save(session));
    }

    @Override
    @Transactional
    public FocusSessionResponse updateSession(UUID userId, UUID sessionId, FocusSessionRequest request) {
        FocusSession session = focusSessionRepository.findByIdAndUserId(sessionId, userId)
                .orElseThrow(FocusSessionNotFoundException::new);

        applySessionRequest(session, request, false);
        return toSessionResponse(focusSessionRepository.save(session));
    }

    @Override
    @Transactional
    public FocusRoundResponse createRound(UUID userId, UUID sessionId, FocusRoundRequest request) {
        FocusSession session = focusSessionRepository.findByIdAndUserId(sessionId, userId)
                .orElseThrow(FocusSessionNotFoundException::new);

        if (request.clientRoundId() != null) {
            var existing = focusRoundRepository.findByUserIdAndClientRoundId(userId, request.clientRoundId());
            if (existing.isPresent()) {
                return toRoundResponse(existing.get());
            }
        }

        FocusRound round = new FocusRound();
        round.setUser(session.getUser());
        round.setSession(session);
        applyRoundRequest(round, request, true);
        return toRoundResponse(focusRoundRepository.save(round));
    }

    @Override
    @Transactional
    public FocusRoundResponse updateRound(UUID userId, UUID sessionId, UUID roundId, FocusRoundRequest request) {
        FocusRound round = focusRoundRepository.findByIdAndUserIdAndSessionId(roundId, userId, sessionId)
                .orElseThrow(FocusRoundNotFoundException::new);

        applyRoundRequest(round, request, false);
        return toRoundResponse(focusRoundRepository.save(round));
    }

    private User getUser(UUID userId) {
        return userRepository.findById(userId)
                .orElseThrow(UserNotFoundException::new);
    }

    private void applySessionRequest(FocusSession session, FocusSessionRequest request, boolean create) {
        if (create) {
            session.setClientSessionId(request.clientSessionId());
        }

        session.setStartAt(request.startAt());
        session.setEndAt(request.endAt());
        session.setStatus(trimOrDefault(request.status(), "active"));
        session.setEndReason(trimOrNull(request.endReason()));
        session.setMode(trimOrDefault(request.mode(), "focus_monitoring"));
        session.setTimezone(trimOrDefault(request.timezone(), "Asia/Taipei"));
        session.setTargetSeconds(request.targetSeconds());
        session.setMonitoredSeconds(valueOrZero(request.monitoredSeconds()));
        session.setFocusSeconds(valueOrZero(request.focusSeconds()));
        session.setDistractedSeconds(valueOrZero(request.distractedSeconds()));
        session.setAttentionSeconds(valueOrZero(request.attentionSeconds()));
        session.setFatigueSeconds(valueOrZero(request.fatigueSeconds()));
        session.setDrowsySeconds(valueOrZero(request.drowsySeconds()));
        session.setPostureDownSeconds(valueOrZero(request.postureDownSeconds()));
        session.setAwaySeconds(valueOrZero(request.awaySeconds()));
        session.setPausedSeconds(valueOrZero(request.pausedSeconds()));
        session.setBreakSeconds(valueOrZero(request.breakSeconds()));
        session.setReminderCount(valueOrZero(request.reminderCount()));
        session.setSummary(copyMap(request.summary()));
        session.setConfig(copyMap(request.config()));
        session.setRevision(valueOrZero(request.revision()));
        session.setSchemaVersion(valueOrDefault(request.schemaVersion(), 1));
    }

    private void applyRoundRequest(FocusRound round, FocusRoundRequest request, boolean create) {
        if (create) {
            round.setClientRoundId(request.clientRoundId());
        }

        round.setRoundNumber(request.roundNumber());
        round.setRoundType(trimOrDefault(request.roundType(), "focus"));
        round.setStatus(trimOrDefault(request.status(), "active"));
        round.setTargetSeconds(request.targetSeconds());
        round.setActualSeconds(valueOrZero(request.actualSeconds()));
        round.setPausedSeconds(valueOrZero(request.pausedSeconds()));
        round.setStartAt(request.startAt() == null ? OffsetDateTime.now() : request.startAt());
        round.setEndAt(request.endAt());
        round.setEndReason(trimOrNull(request.endReason()));
        round.setSchemaVersion(valueOrDefault(request.schemaVersion(), 1));
    }

    private FocusSessionResponse toSessionResponse(FocusSession session) {
        return new FocusSessionResponse(
                session.getId(),
                session.getUser().getId(),
                session.getClientSessionId(),
                session.getStartAt(),
                session.getEndAt(),
                session.getStatus(),
                session.getEndReason(),
                session.getMode(),
                session.getTimezone(),
                session.getTargetSeconds(),
                session.getMonitoredSeconds(),
                session.getFocusSeconds(),
                session.getDistractedSeconds(),
                session.getAttentionSeconds(),
                session.getFatigueSeconds(),
                session.getDrowsySeconds(),
                session.getPostureDownSeconds(),
                session.getAwaySeconds(),
                session.getPausedSeconds(),
                session.getBreakSeconds(),
                session.getReminderCount(),
                session.getSummary(),
                session.getConfig(),
                session.getRevision(),
                session.getSchemaVersion()
        );
    }

    private FocusRoundResponse toRoundResponse(FocusRound round) {
        return new FocusRoundResponse(
                round.getId(),
                round.getUser().getId(),
                round.getSession().getId(),
                round.getClientRoundId(),
                round.getRoundNumber(),
                round.getRoundType(),
                round.getStatus(),
                round.getTargetSeconds(),
                round.getActualSeconds(),
                round.getPausedSeconds(),
                round.getStartAt(),
                round.getEndAt(),
                round.getEndReason(),
                round.getSchemaVersion()
        );
    }

    private static int valueOrZero(Integer value) {
        return value == null ? 0 : value;
    }

    private static int valueOrDefault(Integer value, int fallback) {
        return value == null ? fallback : value;
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
