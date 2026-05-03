package desk_companion_backend.user.repository;

import desk_companion_backend.user.entity.AccountStatus;
import desk_companion_backend.user.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.UUID;

public interface UserRepository extends JpaRepository<User, UUID> {
    Optional<User> findByEmail(String email);

    Optional<User> findByGoogleId(String googleId);

    boolean existsByGoogleId(String googleId);

    boolean existsByEmailAndAccountStatus(String email, AccountStatus accountStatus);
}
