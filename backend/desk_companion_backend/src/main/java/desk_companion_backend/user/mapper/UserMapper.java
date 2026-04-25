package desk_companion_backend.user.mapper;

import desk_companion_backend.user.dto.ProfileResponse;
import desk_companion_backend.user.dto.UserResponse;
import desk_companion_backend.user.entity.Profile;
import desk_companion_backend.user.entity.User;
import org.springframework.stereotype.Component;

@Component
public class UserMapper {

    public UserResponse toResponse(User user) {
        return new UserResponse(
                user.getId(),
                user.getEmail(),
                user.getAuthProvider().name(),
                user.isEmailVerified(),
                user.getAccountStatus().name(),
                user.getCreatedAt(),
                user.getUpdatedAt(),
                user.getProfile() != null ? toProfileResponse(user.getProfile()) : null
        );
    }

    public ProfileResponse toProfileResponse(Profile profile) {
        return new ProfileResponse(
                profile.getId(),
                profile.getDisplayName(),
                profile.getAvatarUrl(),
                profile.getCreatedAt(),
                profile.getUpdatedAt()
        );
    }
}