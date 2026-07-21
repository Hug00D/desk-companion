package desk_companion_backend.focus.service;

import desk_companion_backend.focus.dto.StatisticsSummaryResponse;

import java.time.OffsetDateTime;
import java.util.UUID;

public interface StatisticsService {

    StatisticsSummaryResponse getSummary(UUID userId, OffsetDateTime from, OffsetDateTime to, String timezone);
}
