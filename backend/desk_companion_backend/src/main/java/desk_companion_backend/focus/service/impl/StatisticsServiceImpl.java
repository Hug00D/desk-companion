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

        int focusSeconds = sessions.stream().mapToInt(FocusSession::getFocusSeconds).sum();
        int attentionSeconds = sessions.stream().mapToInt(FocusSession::getAttentionSeconds).sum();
        int fatigueSeconds = sessions.stream().mapToInt(FocusSession::getFatigueSeconds).sum();
        int awaySeconds = sessions.stream().mapToInt(FocusSession::getAwaySeconds).sum();
        int reminderCount = sessions.stream().mapToInt(FocusSession::getReminderCount).sum();
        long completedRoundCount = rounds.stream()
                .filter(round -> "completed".equals(round.getStatus()))
                .count();

        var today = new StatisticsSummaryResponse.TodayStatistics(
                focusSeconds,
                completedRoundCount,
                reminderCount,
                awaySeconds
        );

        var stateDistribution = new StatisticsSummaryResponse.StateDistribution(
                focusSeconds,
                attentionSeconds,
                fatigueSeconds,
                awaySeconds
        );

        return new StatisticsSummaryResponse(
                today,
                buildWeeklyTrend(sessions, from, to, zoneId),
                stateDistribution,
                recentEvents.stream().map(this::toRecentEvent).toList()
        );
    }

    private List<StatisticsSummaryResponse.WeeklyFocusPoint> buildWeeklyTrend(
            List<FocusSession> sessions,
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
            totals.focusSeconds += session.getFocusSeconds();
            totals.attentionSeconds += session.getAttentionSeconds();
            totals.fatigueSeconds += session.getFatigueSeconds();
            totals.awaySeconds += session.getAwaySeconds();
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

    private static class DayTotals {
        int focusSeconds;
        int attentionSeconds;
        int fatigueSeconds;
        int awaySeconds;

        Double focusScore() {
            int total = focusSeconds + attentionSeconds + fatigueSeconds + awaySeconds;
            if (total <= 0) {
                return null;
            }
            return Math.round((focusSeconds * 10000.0 / total)) / 100.0;
        }
    }
}
