package desk_companion_backend.user.repository;

import desk_companion_backend.user.entity.VerificationToken;
import desk_companion_backend.user.entity.VerificationTokenType;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.OffsetDateTime;
import java.util.Optional;
import java.util.UUID;

public interface VerificationTokenRepository extends JpaRepository<VerificationToken, UUID> {

    Optional<VerificationToken> findByTokenHashAndTokenType(String tokenHash, VerificationTokenType tokenType);

    Optional<VerificationToken> findByUserIdAndTokenTypeAndUsedAtIsNullAndExpiresAtAfter(
            UUID userId,
            VerificationTokenType tokenType,
            OffsetDateTime now
    );

    Optional<VerificationToken> findTopByUserIdAndTokenTypeOrderByCreatedAtDesc(
            UUID userId,
            VerificationTokenType tokenType
    );
}
