package desk_companion_backend.auth;

import desk_companion_backend.auth.dto.ConfirmAccountRecoveryRequest;
import desk_companion_backend.auth.dto.ForgotPasswordRequest;
import desk_companion_backend.auth.dto.LoginRequest;
import desk_companion_backend.auth.dto.RequestAccountRecoveryRequest;
import desk_companion_backend.auth.dto.ResetPasswordRequest;
import desk_companion_backend.auth.service.impl.AuthServiceImpl;
import desk_companion_backend.common.exception.AccountDeletedException;
import desk_companion_backend.common.exception.InvalidCredentialsException;
import desk_companion_backend.user.entity.AccountStatus;
import desk_companion_backend.user.entity.AuthProvider;
import desk_companion_backend.user.entity.User;
import desk_companion_backend.user.entity.VerificationToken;
import desk_companion_backend.user.entity.VerificationTokenType;
import desk_companion_backend.user.repository.UserRepository;
import desk_companion_backend.user.repository.VerificationTokenRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.time.OffsetDateTime;
import java.util.Optional;
import java.util.UUID;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class AuthServiceImplTest {

    private UserRepository userRepository;
    private VerificationTokenRepository tokenRepository;
    private PasswordEncoder passwordEncoder;
    private AuthServiceImpl service;

    @BeforeEach
    void setUp() {
        userRepository = mock(UserRepository.class);
        tokenRepository = mock(VerificationTokenRepository.class);
        passwordEncoder = mock(PasswordEncoder.class);
        service = new AuthServiceImpl(
                userRepository,
                tokenRepository,
                passwordEncoder,
                true,
                "1234"
        );
    }

    @Test
    void deletedAccountIsOnlyRevealedAfterPasswordMatches() {
        User user = user(AccountStatus.DELETED);
        when(userRepository.findByEmail("test@gmail.com")).thenReturn(Optional.of(user));
        when(passwordEncoder.matches("WrongPass1!", user.getPasswordHash())).thenReturn(false);
        when(passwordEncoder.matches("Password123!", user.getPasswordHash())).thenReturn(true);

        assertThrows(
                InvalidCredentialsException.class,
                () -> service.login(new LoginRequest("test@gmail.com", "WrongPass1!"))
        );
        assertThrows(
                AccountDeletedException.class,
                () -> service.login(new LoginRequest("test@gmail.com", "Password123!"))
        );
    }

    @Test
    void forgotPasswordExposesDemoCodeButStoresUniqueRandomToken() {
        User user = user(AccountStatus.ACTIVE);
        when(userRepository.findByEmail("test@gmail.com")).thenReturn(Optional.of(user));
        when(tokenRepository.findTopByUserIdAndTokenTypeOrderByCreatedAtDesc(
                user.getId(),
                VerificationTokenType.PASSWORD_RESET
        )).thenReturn(Optional.empty());
        when(tokenRepository.findByUserIdAndTokenTypeAndUsedAtIsNullAndExpiresAtAfter(
                any(),
                any(),
                any()
        )).thenReturn(Optional.empty());

        var response = service.forgotPassword(new ForgotPasswordRequest("test@gmail.com"));

        assertEquals("1234", response.resetToken());
        ArgumentCaptor<VerificationToken> captor = ArgumentCaptor.forClass(VerificationToken.class);
        verify(tokenRepository).save(captor.capture());
        assertNotNull(captor.getValue().getTokenHash());
        assertEquals(64, captor.getValue().getTokenHash().length());
        assertNotEquals("1234", captor.getValue().getTokenHash());
    }

    @Test
    void demoCodeCanResetPasswordOnlyWithAnActiveEmailScopedToken() {
        User user = user(AccountStatus.ACTIVE);
        VerificationToken token = token(user, VerificationTokenType.PASSWORD_RESET);
        when(userRepository.findByEmail("test@gmail.com")).thenReturn(Optional.of(user));
        when(userRepository.findById(user.getId())).thenReturn(Optional.of(user));
        when(tokenRepository.findByUserIdAndTokenTypeAndUsedAtIsNullAndExpiresAtAfter(
                eq(user.getId()),
                eq(VerificationTokenType.PASSWORD_RESET),
                any()
        )).thenReturn(Optional.of(token));
        when(passwordEncoder.matches("NewPassword1!", user.getPasswordHash())).thenReturn(false);
        when(passwordEncoder.encode("NewPassword1!")).thenReturn("new-hash");

        service.resetPassword(
                new ResetPasswordRequest("test@gmail.com", "1234", "NewPassword1!")
        );

        assertEquals("new-hash", user.getPasswordHash());
        assertNotNull(token.getUsedAt());
    }

    @Test
    void recoveryChecksPasswordAndRestoresDeletedAccountWithDemoCode() {
        User user = user(AccountStatus.DELETED);
        when(userRepository.findByEmail("test@gmail.com")).thenReturn(Optional.of(user));
        when(passwordEncoder.matches("Password123!", user.getPasswordHash())).thenReturn(true);
        when(tokenRepository.findTopByUserIdAndTokenTypeOrderByCreatedAtDesc(
                user.getId(),
                VerificationTokenType.ACCOUNT_RECOVERY
        )).thenReturn(Optional.empty());
        when(tokenRepository.findByUserIdAndTokenTypeAndUsedAtIsNullAndExpiresAtAfter(
                eq(user.getId()),
                eq(VerificationTokenType.ACCOUNT_RECOVERY),
                any()
        )).thenReturn(Optional.empty());

        var response = service.requestAccountRecovery(
                new RequestAccountRecoveryRequest("test@gmail.com", "Password123!")
        );
        assertEquals("1234", response.recoveryToken());

        ArgumentCaptor<VerificationToken> captor = ArgumentCaptor.forClass(VerificationToken.class);
        verify(tokenRepository).save(captor.capture());
        VerificationToken token = captor.getValue();
        when(tokenRepository.findByUserIdAndTokenTypeAndUsedAtIsNullAndExpiresAtAfter(
                eq(user.getId()),
                eq(VerificationTokenType.ACCOUNT_RECOVERY),
                any()
        )).thenReturn(Optional.of(token));
        when(userRepository.findById(user.getId())).thenReturn(Optional.of(user));

        service.confirmAccountRecovery(
                new ConfirmAccountRecoveryRequest("test@gmail.com", "1234")
        );

        assertEquals(AccountStatus.ACTIVE, user.getAccountStatus());
        assertNotNull(token.getUsedAt());
    }

    private User user(AccountStatus status) {
        User user = new User();
        user.setId(UUID.randomUUID());
        user.setEmail("test@gmail.com");
        user.setPasswordHash("stored-hash");
        user.setAuthProvider(AuthProvider.EMAIL);
        user.setAccountStatus(status);
        return user;
    }

    private VerificationToken token(User user, VerificationTokenType type) {
        VerificationToken token = new VerificationToken();
        token.setUserId(user.getId());
        token.setTokenType(type);
        token.setTokenHash("a".repeat(64));
        token.setExpiresAt(OffsetDateTime.now().plusMinutes(30));
        return token;
    }
}
