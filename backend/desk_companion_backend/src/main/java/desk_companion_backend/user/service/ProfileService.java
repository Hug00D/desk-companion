package desk_companion_backend.user.service;

import desk_companion_backend.user.dto.ProfileResponse;
import desk_companion_backend.user.dto.UpdateProfileRequest;
import desk_companion_backend.user.entity.Profile;
import desk_companion_backend.user.entity.User;

import java.util.UUID;

public interface ProfileService {

    Profile createProfile(User user, String displayName, String avatarUrl);

    ProfileResponse updateProfile(UUID userId, UpdateProfileRequest request);

    ProfileResponse getProfile(UUID userId);
}