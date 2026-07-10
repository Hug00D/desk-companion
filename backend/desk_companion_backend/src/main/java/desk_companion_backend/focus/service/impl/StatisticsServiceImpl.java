package desk_companion_backend.focus.service.impl;

import desk_companion_backend.common.exception.UserNotFoundException;
import desk_companion_backend.focus.dto.StatisticsSummaryResponse;
import desk_companion_backend.focus.entity.BehaviorEvent;
import desk_companion_backend.focus.entity.FocusRound;
import desk_companion_backend.focus.entity.FocusSession;
import desk_companion_backend.focus.repository.BehaviorEventRepository;
import desk_companion_backend.focus.repository.FocusRoundRepository;
import desk_companion_backend.focus.repository.FocusSessionRepository;
import desk_companion_backend.focus.service.StatisticsService;
import desk_companion_backend.user.repository.UserRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@Service
@Transactional(readOnly = true)
public class StatisticsServiceImpl implements StatisticsService {

    private final UserRepository userRepository;
    private final FocusSessionRepository focusSessionRepository;
    private final FocusRoundRepository focusRoundRepository;
    private final BehaviorEventRepository behaviorEventRepository;

    public StatisticsServiceImpl(
            UserRepository userRepository,
            FocusSessionRepository focusSessionRepository,
            FocusRoundRepository focusRoundRepository,
            BehaviorEventRepository behaviorEventRepository
    ) {
        this.userRepository = userRepository;
        this.focusSessionRepository = focusSessionRepository;
        this.focusRoundRepository = focusRoundRepository;
        this.behaviorEventRepository = behaviorEventRepository;
    }

    @Override
    public StatisticsSummaryResponse getSummary(UUID userId, OffsetDateTime from, OffsetDateTime to, String timezone) {
        if (!userRepository.existsById(userId)) {
            throw new UserNotFoundException();
        }

        ZoneId zoneId = resolveZoneId(timezone);
        List<FocusSession> sessions = focusSessionRepository.findByUserIdAndStartAtBetweenOrderByStartAtAsc(
                userId,
                from,
                to
        );
        List<FocusRound> rounds = focusRoundRepository.findByUserIdAndStartAtBetweenOrderByStartAtAsc(
                userId,
                from,
                to
        );
        List<BehaviorEvent> recentEvents = behaviorEventRepository.findTop20ByUserIdAndTsBetweenOrderByTsDesc(
                userId,
                from,
                to
        );
        List<BehaviorEvent> events = behaviorEventRepository.findByUserIdAndTsBetweenOrderByTsAsc(
                userId,
                from,
                to
        );

        StateTotals eventDurationTotals = buildEventDurationTotals(events);
        StateTotals sessionTotals = buildSessionTotals(sessions, eventDurationTotals);
        int reminderCount = sessions.stream().mapToInt(FocusSession::getReminderCount).sum();
        long completedRoundCount = rounds.stream()
                .filter(round -> "completed".equals(round.getStatus()))
                .count();

        var today = new StatisticsSummaryResponse.TodayStatistics(
                sessionTotals.focusSeconds,
                completedRoundCount,
                reminderCount + Math.toIntExact(eventDurationTotals.reminderCount),
                sessionTotals.awaySeconds
        );

        var stateDistribution = new StatisticsSummaryResponse.StateDistribution(
                sessionTotals.focusSeconds,
                sessionTotals.attentionSeconds,
                sessionTotals.distractedSeconds,
                sessionTotals.fatigueSeconds,
                sessionTotals.drowsySeconds,
                sessionTotals.postureDownSeconds,
                sessionTotals.awaySeconds
        );

        return new StatisticsSummaryResponse(
                today,
                buildWeeklyTrend(sessions, events, from, to, zoneId),
                stateDistribution,
                buildEventCounts(events),
                recentEvents.stream().map(this::toRecentEvent).toList()
        );
    }

    private StateTotals buildSessionTotals(List<FocusSession> sessions, StateTotals eventFallback) {
        StateTotals totals = new StateTotals();
        for (FocusSession session : sessions) {
            totals.addSession(session);
        }
        totals.applyEventFallback(eventFallback);
        return totals;
    }

    private StateTotals buildEventDurationTotals(List<BehaviorEvent> events) {
        StateTotals totals = new StateTotals();
        for (BehaviorEvent event : events) {
            int seconds = durationSeconds(event);
            totals.addEvent(event.getEventType(), seconds);
        }
        return totals;
    }

    private Map<String, Long> buildEventCounts(List<BehaviorEvent> events) {
        Map<String, Long> counts = new LinkedHashMap<>();
        for (BehaviorEvent event : events) {
            String eventType = event.getEventType();
            if (eventType == null || eventType.isBlank()) {
                eventType = "unknown";
            }
            counts.put(eventType, counts.getOrDefault(eventType, 0L) + 1L);
        }
        return counts;
    }

    private List<StatisticsSummaryResponse.WeeklyFocusPoint> buildWeeklyTrend(
            List<FocusSession> sessions,
            List<BehaviorEvent> events,
            OffsetDateTime from,
            OffsetDateTime to,
            ZoneId zoneId
    ) {
        LocalDate startDate = from.atZoneSameInstant(zoneId).toLocalDate();
        LocalDate endDate = to.atZoneSameInstant(zoneId).toLocalDate();
        Map<LocalDate, DayTotals> totalsByDate = new LinkedHashMap<>();

        for (LocalDate date = startDate; !date.isAfter(endDate); date = date.plusDays(1)) {
            totalsByDate.put(date, new DayTotals());
        }

        for (FocusSession session : sessions) {
            LocalDate date = session.getStartAt().atZoneSameInstant(zoneId).toLocalDate();
            DayTotals totals = totalsByDate.computeIfAbsent(date, ignored -> new DayTotals());
            totals.addSession(session);
        }

        for (BehaviorEvent event : events) {
            LocalDate date = event.getTs().atZoneSameInstant(zoneId).toLocalDate();
            DayTotals totals = totalsByDate.computeIfAbsent(date, ignored -> new DayTotals());
            totals.addEventFallback(event.getEventType(), durationSeconds(event));
        }

        var result = new ArrayList<StatisticsSummaryResponse.WeeklyFocusPoint>();
        totalsByDate.forEach((date, totals) -> result.add(
                new StatisticsSummaryResponse.WeeklyFocusPoint(
                        date,
                        totals.focusSeconds,
                        totals.focusScore()
                )
        ));
        return result;
    }

    private StatisticsSummaryResponse.RecentStatisticsEvent toRecentEvent(BehaviorEvent event) {
        String detail = event.getActionTriggered();
        if (detail == null || detail.isBlank()) {
            detail = event.getDetectedObject();
        }

        return new StatisticsSummaryResponse.RecentStatisticsEvent(
                event.getEventType(),
                event.getTs(),
                event.getEventType(),
                detail,
                event.getSeverity(),
                event.getOutcome()
        );
    }

    private ZoneId resolveZoneId(String timezone) {
        if (timezone == null || timezone.isBlank()) {
            return ZoneId.of("Asia/Taipei");
        }
        try {
            return ZoneId.of(timezone);
        } catch (Exception ignored) {
            return ZoneId.of("Asia/Taipei");
        }
    }

    private int durationSeconds(BehaviorEvent event) {
        Integer durationMs = event.getDurationMs();
        if (durationMs == null || durationMs <= 0) {
            return 0;
        }
        return Math.max(1, (int) Math.round(durationMs / 1000.0));
    }

    private static int inferredFocusSeconds(FocusSession session) {
        int abnormalSeconds = session.getAttentionSeconds()
                + session.getDistractedSeconds()
                + session.getFatigueSeconds()
                + session.getDrowsySeconds()
                + session.getPostureDownSeconds()
                + session.getAwaySeconds();
        int explicitFocusSeconds = session.getFocusSeconds();
        if (explicitFocusSeconds > 0) {
            return explicitFocusSeconds;
        }
        return Math.max(0, session.getMonitoredSeconds() - abnormalSeconds);
    }

    private static class StateTotals {
        int focusSeconds;
        int attentionSeconds;
        int distractedSeconds;
        int fatigueSeconds;
        int drowsySeconds;
        int postureDownSeconds;
        int awaySeconds;
        long reminderCount;

        int totalSeconds() {
            return focusSeconds
                    + attentionSeconds
                    + distractedSeconds
                    + fatigueSeconds
                    + drowsySeconds
                    + postureDownSeconds
                    + awaySeconds;
        }

        void addSession(FocusSession session) {
            focusSeconds += inferredFocusSeconds(session);
            attentionSeconds += session.getAttentionSeconds();
            distractedSeconds += session.getDistractedSeconds();
            fatigueSeconds += session.getFatigueSeconds();
            drowsySeconds += session.getDrowsySeconds();
            postureDownSeconds += session.getPostureDownSeconds();
            awaySeconds += session.getAwaySeconds();
        }

        void addEvent(String eventType, int seconds) {
            if (eventType == null) {
                return;
            }
            switch (eventType) {
                case "vision.attention_warning", "vision.partial_user_detected" -> {
                    attentionSeconds += seconds;
                    reminderCount += 1;
                }
                case "vision.distracted" -> {
                    distractedSeconds += seconds;
                    reminderCount += 1;
                }
                case "vision.fatigue_detected" -> {
                    fatigueSeconds += seconds;
                    reminderCount += 1;
                }
                case "vision.drowsy_detected" -> {
                    drowsySeconds += seconds;
                    reminderCount += 1;
                }
                case "vision.posture_down" -> {
                    postureDownSeconds += seconds;
                    reminderCount += 1;
                }
                case "vision.user_away" -> awaySeconds += seconds;
                default -> {
                }
            }
        }

        void applyEventFallback(StateTotals eventFallback) {
            if (eventFallback == null || eventFallback.totalSeconds() == 0) {
                return;
            }
            if (attentionSeconds == 0) {
                attentionSeconds = eventFallback.attentionSeconds;
            }
            if (distractedSeconds == 0) {
                distractedSeconds = eventFallback.distractedSeconds;
            }
            if (fatigueSeconds == 0) {
                fatigueSeconds = eventFallback.fatigueSeconds;
            }
            if (drowsySeconds == 0) {
                drowsySeconds = eventFallback.drowsySeconds;
            }
            if (postureDownSeconds == 0) {
                postureDownSeconds = eventFallback.postureDownSeconds;
            }
            if (awaySeconds == 0) {
                awaySeconds = eventFallback.awaySeconds;
            }
        }
    }

    private static class DayTotals extends StateTotals {
        void addEventFallback(String eventType, int seconds) {
            if (eventType == null || seconds <= 0) {
                return;
            }
            switch (eventType) {
                case "vision.attention_warning", "vision.partial_user_detected" -> {
                    attentionSeconds += seconds;
                }
                case "vision.distracted" -> {
                    distractedSeconds += seconds;
                }
                case "vision.fatigue_detected" -> {
                    fatigueSeconds += seconds;
                }
                case "vision.drowsy_detected" -> {
                    drowsySeconds += seconds;
                }
                case "vision.posture_down" -> {
                    postureDownSeconds += seconds;
                }
                case "vision.user_away" -> {
                    awaySeconds += seconds;
                }
                default -> {
                }
            }
        }

        Double focusScore() {
            int total = totalSeconds();
            if (total <= 0) {
                return null;
            }
            return Math.round((focusSeconds * 10000.0 / total)) / 100.0;
        }
    }
}
