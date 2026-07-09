package desk_companion_backend.focus.repository;

import desk_companion_backend.focus.entity.BehaviorEvent;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.OffsetDateTime;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface BehaviorEventRepository extends JpaRepository<BehaviorEvent, Long> {

    Optional<BehaviorEvent> findByUserIdAndClientEventId(UUID userId, UUID clientEventId);

    List<BehaviorEvent> findTop20ByUserIdAndTsBetweenOrderByTsDesc(
            UUID userId,
            OffsetDateTime from,
            OffsetDateTime to
    );

    List<BehaviorEvent> findByUserIdAndTsBetweenOrderByTsAsc(
            UUID userId,
            OffsetDateTime from,
            OffsetDateTime to
    );
}
