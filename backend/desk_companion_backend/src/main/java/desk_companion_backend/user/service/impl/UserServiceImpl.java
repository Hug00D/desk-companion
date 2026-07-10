package desk_companion_backend.user.service.impl;

import desk_companion_backend.common.exception.AccountDeletedException;
import desk_companion_backend.common.exception.AccountSuspendedException;
import desk_companion_backend.common.exception.EmailAlreadyExistsException;
import desk_companion_backend.common.exception.InvalidAccountStatusException;
import desk_companion_backend.common.exception.InvalidCredentialsException;
import desk_companion_backend.common.exception.UserNotFoundException;
import desk_companion_backend.user.dto.AccountStatusCheckResponse;
import desk_companion_backend.user.dto.RegisterUserRequest;
import desk_companion_backend.user.dto.UserResponse;
import desk_companion_backend.user.entity.AccountStatus;
import desk_companion_backend.user.entity.AuthProvider;
import desk_companion_backend.user.entity.Profile;
import desk_companion_backend.user.entity.User;
import desk_companion_backend.user.mapper.UserMapper;
import desk_companion_backend.user.repository.UserRepository;
import desk_companion_backend.user.service.ProfileService;
import desk_companion_backend.user.service.UserService;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.UUID;

@Service
@Transactional(readOnly = true)
public class UserServiceImpl implements UserService {

    private final UserRepository userRepository;
    private final ProfileService profileService;
    private final UserMapper userMapper;
    private final PasswordEncoder passwordEncoder;

    public UserServiceImpl(
            UserRepository userRepository,
            ProfileService profileService,
            UserMapper userMapper,
            PasswordEncoder passwordEncoder
    ) {
        this.userRepository = userRepository;
        this.profileService = profileService;
        this.userMapper = userMapper;
        this.passwordEncoder = passwordEncoder;
    }

    @Override
    @Transactional
    public UserResponse register(RegisterUserRequest request) {
        String normalizedEmail = normalizeEmail(request.email());

        userRepository.findByEmail(normalizedEmail).ifPresent(existingUser -> {
            if (existingUser.getAccountStatus() == AccountStatus.ACTIVE) {
                throw new EmailAlreadyExistsException(normalizedEmail);
            }

            if (existingUser.getAccountStatus() == AccountStatus.DELETED) {
                throw new AccountDeletedException(normalizedEmail);
            }

            if (existingUser.getAccountStatus() == AccountStatus.SUSPENDED) {
                throw new AccountSuspendedException();
            }
        });

        User user = new User();
        user.setEmail(normalizedEmail);
        user.setPasswordHash(passwordEncoder.encode(request.password()));
        user.setAuthProvider(AuthProvider.EMAIL);
        user.setEmailVerified(false);
        user.setAccountStatus(AccountStatus.ACTIVE);

        User savedUser = userRepository.save(user);

        Profile profile = profileService.createProfile(savedUser, request.displayName(), null);
        savedUser.setProfile(profile);

        return userMapper.toResponse(savedUser);
    }

    @Override
    public UserResponse getById(UUID userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(UserNotFoundException::new);
        return userMapper.toResponse(user);
    }

    @Override
    public UserResponse getByEmail(String email) {
        User user = userRepository.findByEmail(normalizeEmail(email))
                .orElseThrow(UserNotFoundException::new);
        return userMapper.toResponse(user);
    }

    @Override
    @Transactional
    public void softDelete(UUID userId, String password) {
        User user = userRepository.findById(userId)
                .orElseThrow(UserNotFoundException::new);

        if (user.getAccountStatus() != AccountStatus.ACTIVE
                || user.getPasswordHash() == null
                || !passwordEncoder.matches(password, user.getPasswordHash())) {
            throw new InvalidCredentialsException();
        }

        user.setAccountStatus(AccountStatus.DELETED);
    }

    @Override
    public AccountStatusCheckResponse checkAccountStatus(UUID userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(UserNotFoundException::new);

        return mapAccountStatus(user.getAccountStatus());
    }

    private AccountStatusCheckResponse mapAccountStatus(AccountStatus status) {
        return switch (status) {
            case ACTIVE -> new AccountStatusCheckResponse("ACTIVE", true, "Login allowed.");
            case SUSPENDED -> new AccountStatusCheckResponse("SUSPENDED", false, "Account is suspended.");
            case DELETED -> new AccountStatusCheckResponse("DELETED", false, "Account is deleted.");
            default -> throw new InvalidAccountStatusException(status.name());
        };
    }

    private String normalizeEmail(String email) {
        return email == null ? null : email.trim().toLowerCase();
    }

    public void assertLoginAllowed(User user) {
        if (user.getAccountStatus() == AccountStatus.SUSPENDED) {
            throw new AccountSuspendedException();
        }
        if (user.getAccountStatus() == AccountStatus.DELETED) {
            throw new AccountDeletedException(user.getEmail());
        }
    }
}
