package desk_companion_backend.user.service.impl;

import desk_companion_backend.auth.dto.GoogleLoginResponse;
import desk_companion_backend.auth.google.GoogleTokenPayload;
import desk_companion_backend.auth.google.GoogleTokenVerifier;
import desk_companion_backend.common.exception.AccountDeletedException;
import desk_companion_backend.common.exception.AccountSuspendedException;
import desk_companion_backend.common.exception.GoogleAccountConflictException;
import desk_companion_backend.user.entity.AccountStatus;
import desk_companion_backend.user.entity.AuthProvider;
import desk_companion_backend.user.entity.Profile;
import desk_companion_backend.user.entity.User;
import desk_companion_backend.user.mapper.UserMapper;
import desk_companion_backend.user.repository.UserRepository;
import desk_companion_backend.user.service.GoogleAuthService;
import desk_companion_backend.user.service.ProfileService;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@Transactional(readOnly = true)
public class GoogleAuthServiceImpl implements GoogleAuthService {

    private final GoogleTokenVerifier googleTokenVerifier;
    private final UserRepository userRepository;
    private final ProfileService profileService;
    private final UserMapper userMapper;

    public GoogleAuthServiceImpl(
            GoogleTokenVerifier googleTokenVerifier,
            UserRepository userRepository,
            ProfileService profileService,
            UserMapper userMapper
    ) {
        this.googleTokenVerifier = googleTokenVerifier;
        this.userRepository = userRepository;
        this.profileService = profileService;
        this.userMapper = userMapper;
    }

    @Override
    @Transactional
    public GoogleLoginResponse loginOrRegister(String idToken) {
        GoogleTokenPayload payload = googleTokenVerifier.verify(idToken);

        String googleId = payload.sub();
        String email = normalizeEmail(payload.email());

        var existingGoogleUserOpt = userRepository.findByGoogleId(googleId);
        if (existingGoogleUserOpt.isPresent()) {
            User existingGoogleUser = existingGoogleUserOpt.get();
            assertLoginAllowed(existingGoogleUser);
            return new GoogleLoginResponse(false, userMapper.toResponse(existingGoogleUser));
        }

        var existingEmailUserOpt = userRepository.findByEmail(email);
        if (existingEmailUserOpt.isPresent()) {
            throw new GoogleAccountConflictException(email);
        }

        User newUser = new User();
        newUser.setGoogleId(googleId);
        newUser.setEmail(email);
        newUser.setPasswordHash(null);
        newUser.setAuthProvider(AuthProvider.GOOGLE);
        newUser.setEmailVerified(payload.emailVerified());
        newUser.setAccountStatus(AccountStatus.ACTIVE);

        User savedUser = userRepository.save(newUser);

        Profile profile = profileService.createProfile(savedUser, null, null);
        savedUser.setProfile(profile);

        return new GoogleLoginResponse(true, userMapper.toResponse(savedUser));
    }

    private void assertLoginAllowed(User user) {
        if (user.getAccountStatus() == AccountStatus.SUSPENDED) {
            throw new AccountSuspendedException();
        }
        if (user.getAccountStatus() == AccountStatus.DELETED) {
            throw new AccountDeletedException();
        }
    }

    private String normalizeEmail(String email) {
        return email == null ? null : email.trim().toLowerCase();
    }
}