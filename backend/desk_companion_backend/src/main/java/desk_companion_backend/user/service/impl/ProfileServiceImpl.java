package desk_companion_backend.user.service.impl;

import desk_companion_backend.common.exception.UserNotFoundException;
import desk_companion_backend.user.dto.ProfileResponse;
import desk_companion_backend.user.dto.UpdateProfileRequest;
import desk_companion_backend.user.entity.Profile;
import desk_companion_backend.user.entity.User;
import desk_companion_backend.user.mapper.UserMapper;
import desk_companion_backend.user.repository.ProfileRepository;
import desk_companion_backend.user.repository.UserRepository;
import desk_companion_backend.user.service.ProfileService;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.UUID;

@Service
@Transactional(readOnly = true)
public class ProfileServiceImpl implements ProfileService {

    private final ProfileRepository profileRepository;
    private final UserRepository userRepository;
    private final UserMapper userMapper;

    public ProfileServiceImpl(
            ProfileRepository profileRepository,
            UserRepository userRepository,
            UserMapper userMapper
    ) {
        this.profileRepository = profileRepository;
        this.userRepository = userRepository;
        this.userMapper = userMapper;
    }

    @Override
    @Transactional
    public Profile createProfile(User user, String displayName, String avatarUrl) {
        Profile profile = new Profile();

        // 如果你是 shared PK + @MapsId，通常只要 setUser(user)
        // 如果目前 entity 還沒設好，可先保守補 setId(user.getId())
        profile.setUser(user);
        profile.setDisplayName(displayName);
        profile.setAvatarUrl(avatarUrl);

        return profileRepository.save(profile);
    }

    @Override
    @Transactional
    public ProfileResponse updateProfile(UUID userId, UpdateProfileRequest request) {
        User user = userRepository.findById(userId)
                .orElseThrow(UserNotFoundException::new);

        Profile profile = user.getProfile();
        if (profile == null) {
            profile = createProfile(user, null, null);
            user.setProfile(profile);
        }

        if (request.displayName() != null) {
            profile.setDisplayName(request.displayName().trim());
        }
        if (request.avatarUrl() != null) {
            profile.setAvatarUrl(request.avatarUrl().trim());
        }

        return userMapper.toProfileResponse(profile);
    }

    @Override
    public ProfileResponse getProfile(UUID userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(UserNotFoundException::new);

        if (user.getProfile() == null) {
            return null;
        }

        return userMapper.toProfileResponse(user.getProfile());
    }
}