package desk_companion_backend.focus.repository;

import desk_companion_backend.focus.entity.UserPreferences;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.UUID;

public interface UserPreferencesRepository extends JpaRepository<UserPreferences, UUID> {
}
