package desk_companion_backend.focus.repository;

import desk_companion_backend.focus.entity.FocusRound;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface FocusRoundRepository extends JpaRepository<FocusRound, UUID> {

    Optional<FocusRound> findByIdAndUserIdAndSessionId(UUID id, UUID userId, UUID sessionId);

    Optional<FocusRound> findByUserIdAndClientRoundId(UUID userId, UUID clientRoundId);

    List<FocusRound> findByUserIdAndStartAtBetweenOrderByStartAtAsc(
            UUID userId,
            OffsetDateTime from,
            OffsetDateTime to
    );
}
