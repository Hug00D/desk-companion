package desk_companion_backend.focus.repository;

import desk_companion_backend.focus.entity.FocusSession;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface FocusSessionRepository extends JpaRepository<FocusSession, UUID> {

    Optional<FocusSession> findByIdAndUserId(UUID id, UUID userId);

    Optional<FocusSession> findByUserIdAndClientSessionId(UUID userId, UUID clientSessionId);

    List<FocusSession> findByUserIdAndStartAtBetweenOrderByStartAtAsc(
            UUID userId,
            OffsetDateTime from,
            OffsetDateTime to
    );
}
