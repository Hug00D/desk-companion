package desk_companion_backend.focus.dto;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;

public record StatisticsSummaryResponse(
        TodayStatistics today,
        List<WeeklyFocusPoint> weeklyTrend,
        StateDistribution stateDistribution,
        Map<String, Long> eventCounts,
        List<RecentStatisticsEvent> recentEvents
) {

    public record TodayStatistics(
            int focusSeconds,
            long completedRoundCount,
            int reminderShownCount,
            int awaySeconds
    ) {
    }

    public record WeeklyFocusPoint(
            LocalDate date,
            int focusSeconds,
            Double focusScore
    ) {
    }

    public record StateDistribution(
            int focusSeconds,
            int attentionSeconds,
            int distractedSeconds,
            int fatigueSeconds,
            int drowsySeconds,
            int postureDownSeconds,
            int awaySeconds
    ) {
    }

    public record RecentStatisticsEvent(
            String eventType,
            OffsetDateTime ts,
            String title,
            String detail,
            String severity,
            String outcome
    ) {
    }
}
