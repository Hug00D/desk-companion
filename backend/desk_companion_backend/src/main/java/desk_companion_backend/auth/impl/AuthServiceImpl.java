package desk_companion_backend.auth.service.impl;

import desk_companion_backend.auth.dto.AuthResponse;
import desk_companion_backend.auth.dto.LoginRequest;
import desk_companion_backend.auth.service.AuthService;
import desk_companion_backend.user.entity.AccountStatus;
import desk_companion_backend.user.entity.User;
import desk_companion_backend.user.repository.UserRepository;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import desk_companion_backend.common.exception.InvalidCredentialsException;
import desk_companion_backend.common.exception.AccountSuspendedException;
import desk_companion_backend.common.exception.AccountDeletedException;

@Service
@Transactional(readOnly = true)
public class AuthServiceImpl implements AuthService {

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;

    public AuthServiceImpl(UserRepository userRepository,
                           PasswordEncoder passwordEncoder) {
        this.userRepository = userRepository;
        this.passwordEncoder = passwordEncoder;
    }

    @Override
    public AuthResponse login(LoginRequest request) {
        String normalizedEmail = request.email().trim().toLowerCase();

        User user = userRepository.findByEmail(normalizedEmail)
                .orElseThrow(InvalidCredentialsException::new);

        if (user.getAccountStatus() == AccountStatus.SUSPENDED) {
            throw new AccountSuspendedException();
        }

        if (user.getAccountStatus() == AccountStatus.DELETED) {
            throw new AccountDeletedException();
        }

        boolean passwordMatched = passwordEncoder.matches(
                request.password(),
                user.getPasswordHash()
        );

        if (!passwordMatched) {
            throw new InvalidCredentialsException();
        }

        return new AuthResponse(
                user.getId(),
                user.getEmail(),
                "Login successful."
        );
    }
}