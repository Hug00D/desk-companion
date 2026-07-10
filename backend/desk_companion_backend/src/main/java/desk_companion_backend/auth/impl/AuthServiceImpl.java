package desk_companion_backend.auth.service.impl;

import desk_companion_backend.auth.dto.AccountRecoveryResponse;
import desk_companion_backend.auth.dto.ActionResponse;
import desk_companion_backend.auth.dto.AuthResponse;
import desk_companion_backend.auth.dto.ConfirmAccountRecoveryRequest;
import desk_companion_backend.auth.dto.ConfirmAccountRecoveryResponse;
import desk_companion_backend.auth.dto.ForgotPasswordRequest;
import desk_companion_backend.auth.dto.ForgotPasswordResponse;
import desk_companion_backend.auth.dto.LoginRequest;
import desk_companion_backend.auth.dto.RequestAccountRecoveryRequest;
import desk_companion_backend.auth.dto.ResetPasswordRequest;
import desk_companion_backend.auth.dto.ValidateResetTokenRequest;
import desk_companion_backend.auth.dto.ValidateResetTokenResponse;
import desk_companion_backend.auth.service.AuthService;
import desk_companion_backend.common.exception.ExpiredPasswordResetTokenException;
import desk_companion_backend.common.exception.ExpiredVerificationTokenException;
import desk_companion_backend.common.exception.AccountDeletedException;
import desk_companion_backend.common.exception.AccountSuspendedException;
import desk_companion_backend.common.exception.InvalidCredentialsException;
import desk_companion_backend.common.exception.InvalidPasswordResetTokenException;
import desk_companion_backend.common.exception.InvalidVerificationTokenException;
import desk_companion_backend.common.exception.InvalidPasswordException;
import desk_companion_backend.user.entity.AccountStatus;
import desk_companion_backend.user.entity.AuthProvider;
import desk_companion_backend.user.entity.User;
import desk_companion_backend.user.entity.VerificationToken;
import desk_companion_backend.user.entity.VerificationTokenType;
import desk_companion_backend.user.repository.UserRepository;
import desk_companion_backend.user.repository.VerificationTokenRepository;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.OffsetDateTime;
import java.util.HexFormat;

@Service
@Transactional(readOnly = true)
public class AuthServiceImpl implements AuthService {

    private static final int TOKEN_BYTES = 32;
    private static final long RESET_TOKEN_EXPIRE_MINUTES = 30;
    private static final long ACCOUNT_RECOVERY_TOKEN_EXPIRE_MINUTES = 30;
    private static final long TOKEN_REQUEST_COOLDOWN_SECONDS = 60;

    private final UserRepository userRepository;
    private final VerificationTokenRepository verificationTokenRepository;
    private final PasswordEncoder passwordEncoder;
    private final SecureRandom secureRandom = new SecureRandom();
    private final boolean returnResetTokenForTesting;
    private final String demoVerificationCode;

    public AuthServiceImpl(
            UserRepository userRepository,
            VerificationTokenRepository verificationTokenRepository,
            PasswordEncoder passwordEncoder,
            @Value("${app.auth.return-reset-token-for-testing:false}") boolean returnResetTokenForTesting,
            @Value("${app.auth.demo-verification-code:}") String demoVerificationCode
    ) {
        this.userRepository = userRepository;
        this.verificationTokenRepository = verificationTokenRepository;
        this.passwordEncoder = passwordEncoder;
        this.returnResetTokenForTesting = returnResetTokenForTesting;
        this.demoVerificationCode = demoVerificationCode == null ? "" : demoVerificationCode.trim();
    }

    @Override
    public AuthResponse login(LoginRequest request) {
        String normalizedEmail = normalizeEmail(request.email());

        User user = userRepository.findByEmail(normalizedEmail)
                .orElseThrow(InvalidCredentialsException::new);

        boolean passwordMatched = user.getPasswordHash() != null
                && passwordEncoder.matches(request.password(), user.getPasswordHash());

        if (!passwordMatched) {
            throw new InvalidCredentialsException();
        }

        assertLoginAllowed(user);

        return new AuthResponse(
                user.getId(),
                user.getEmail(),
                "Login successful."
        );
    }

    @Override
    @Transactional
    public ForgotPasswordResponse forgotPassword(ForgotPasswordRequest request) {
        String normalizedEmail = normalizeEmail(request.email());
        String genericMessage = "If the email exists, password reset instructions have been created.";
        
        var userOpt = userRepository.findByEmail(normalizedEmail);
        if (userOpt.isEmpty()) {
            return new ForgotPasswordResponse(genericMessage, null);
        }

        User user = userOpt.get();
        if (!canIssueResetToken(user)) {
            return new ForgotPasswordResponse(genericMessage, null);
        }

        OffsetDateTime now = OffsetDateTime.now();
        if (isTokenRequestCoolingDown(user, VerificationTokenType.PASSWORD_RESET, now)) {
            return new ForgotPasswordResponse(genericMessage, null);
        }

        markActiveTokensUsed(user, VerificationTokenType.PASSWORD_RESET, now);

        String rawToken = generateRawToken();
        createVerificationToken(
                user,
                rawToken,
                VerificationTokenType.PASSWORD_RESET,
                now.plusMinutes(RESET_TOKEN_EXPIRE_MINUTES)
        );

        return new ForgotPasswordResponse(
                "Password reset token created.",
                exposedVerificationToken(rawToken)
        );
    }

    @Override
    @Transactional
    public ActionResponse resetPassword(ResetPasswordRequest request) {
        VerificationToken token = getValidResetToken(request.token(), request.email());

        User user = userRepository.findById(token.getUserId())
                .orElseThrow(InvalidPasswordResetTokenException::new);
        
        // ✅ 正確寫法：(明文新密碼, 資料庫裡的加密舊密碼)
        if (passwordEncoder.matches(request.newPassword(), user.getPasswordHash())) {
            throw new InvalidPasswordException("新密碼不能與目前密碼相同");
        }

        if (user.getAuthProvider() == AuthProvider.GOOGLE) {
            throw new InvalidPasswordResetTokenException();
        }

        assertLoginAllowed(user);

        user.setPasswordHash(passwordEncoder.encode(request.newPassword()));
        token.setUsedAt(OffsetDateTime.now());

        return new ActionResponse("Password has been reset successfully.");
    }

    @Override
    @Transactional
    public AccountRecoveryResponse requestAccountRecovery(RequestAccountRecoveryRequest request) {
        String normalizedEmail = normalizeEmail(request.email());
        String genericMessage = "If the account can be recovered, recovery instructions have been created.";

        var userOpt = userRepository.findByEmail(normalizedEmail);
        if (userOpt.isEmpty()) {
            return new AccountRecoveryResponse(genericMessage, null);
        }

        User user = userOpt.get();
        if (user.getAccountStatus() != AccountStatus.DELETED) {
            return new AccountRecoveryResponse(genericMessage, null);
        }
        if (user.getPasswordHash() == null
                || !passwordEncoder.matches(request.password(), user.getPasswordHash())) {
            throw new InvalidCredentialsException();
        }

        OffsetDateTime now = OffsetDateTime.now();
        if (isTokenRequestCoolingDown(user, VerificationTokenType.ACCOUNT_RECOVERY, now)) {
            return new AccountRecoveryResponse(genericMessage, null);
        }

        markActiveTokensUsed(user, VerificationTokenType.ACCOUNT_RECOVERY, now);

        String rawToken = generateRawToken();
        createVerificationToken(
                user,
                rawToken,
                VerificationTokenType.ACCOUNT_RECOVERY,
                now.plusMinutes(ACCOUNT_RECOVERY_TOKEN_EXPIRE_MINUTES)
        );

        return new AccountRecoveryResponse(
                "Account recovery token created.",
                exposedVerificationToken(rawToken)
        );
    }

    @Override
    @Transactional
    public ConfirmAccountRecoveryResponse confirmAccountRecovery(ConfirmAccountRecoveryRequest request) {
        VerificationToken token = getValidAccountRecoveryToken(request.token(), request.email());

        User user = userRepository.findById(token.getUserId())
                .orElseThrow(InvalidVerificationTokenException::new);

        if (user.getAccountStatus() != AccountStatus.DELETED) {
            throw new InvalidVerificationTokenException();
        }

        user.setAccountStatus(AccountStatus.ACTIVE);
        token.setUsedAt(OffsetDateTime.now());

        return new ConfirmAccountRecoveryResponse("Account has been restored successfully.");
    }

    @Override
    public ValidateResetTokenResponse validateResetToken(ValidateResetTokenRequest request) {
        try {
            getValidResetToken(request.token(), request.email());
            return new ValidateResetTokenResponse(true, "Reset token is valid.");
        } catch (InvalidPasswordResetTokenException | ExpiredPasswordResetTokenException ex) {
            return new ValidateResetTokenResponse(false, ex.getMessage());
        }
    }

    private boolean canIssueResetToken(User user) {
        if (user.getAccountStatus() != AccountStatus.ACTIVE) {
            return false;
        }

        return (user.getAuthProvider() == AuthProvider.EMAIL || user.getAuthProvider() == AuthProvider.BOTH)
                && user.getPasswordHash() != null;
    }

    private void assertLoginAllowed(User user) {
        if (user.getAccountStatus() == AccountStatus.SUSPENDED) {
            throw new AccountSuspendedException();
        }
        if (user.getAccountStatus() == AccountStatus.DELETED) {
            throw new AccountDeletedException(user.getEmail());
        }
    }

    private boolean isTokenRequestCoolingDown(
            User user,
            VerificationTokenType tokenType,
            OffsetDateTime now
    ) {
        var latestTokenOpt = verificationTokenRepository.findTopByUserIdAndTokenTypeOrderByCreatedAtDesc(
                user.getId(),
                tokenType
        );

        return latestTokenOpt
                .map(VerificationToken::getCreatedAt)
                .filter(lastIssuedAt -> lastIssuedAt.plusSeconds(TOKEN_REQUEST_COOLDOWN_SECONDS).isAfter(now))
                .isPresent();
    }

    private void markActiveTokensUsed(User user, VerificationTokenType tokenType, OffsetDateTime now) {
        verificationTokenRepository
                .findByUserIdAndTokenTypeAndUsedAtIsNullAndExpiresAtAfter(
                        user.getId(),
                        tokenType,
                        now
                )
                .ifPresent(token -> {
                    token.setUsedAt(now);
                    verificationTokenRepository.save(token);
                });
    }

    private void createVerificationToken(
            User user,
            String rawToken,
            VerificationTokenType tokenType,
            OffsetDateTime expiresAt
    ) {
        VerificationToken tokenEntity = new VerificationToken();
        tokenEntity.setUserId(user.getId());
        tokenEntity.setTokenHash(hashToken(rawToken));
        tokenEntity.setTokenType(tokenType);
        tokenEntity.setExpiresAt(expiresAt);
        verificationTokenRepository.save(tokenEntity);
    }

    private VerificationToken getValidResetToken(String rawToken, String email) {
        if (isDemoVerificationCode(rawToken)) {
            return getLatestValidTokenForEmail(email, VerificationTokenType.PASSWORD_RESET);
        }

        String tokenHash = hashToken(rawToken);

        VerificationToken token = verificationTokenRepository
                .findByTokenHashAndTokenType(tokenHash, VerificationTokenType.PASSWORD_RESET)
                .orElseThrow(InvalidPasswordResetTokenException::new);

        if (token.getUsedAt() != null) {
            throw new InvalidPasswordResetTokenException();
        }

        if (token.getExpiresAt().isBefore(OffsetDateTime.now())) {
            throw new ExpiredPasswordResetTokenException();
        }

        return token;
    }

    private VerificationToken getValidAccountRecoveryToken(String rawToken, String email) {
        if (isDemoVerificationCode(rawToken)) {
            return getLatestValidTokenForEmail(email, VerificationTokenType.ACCOUNT_RECOVERY);
        }

        String tokenHash = hashToken(rawToken);

        VerificationToken token = verificationTokenRepository
                .findByTokenHashAndTokenType(tokenHash, VerificationTokenType.ACCOUNT_RECOVERY)
                .orElseThrow(InvalidVerificationTokenException::new);

        if (token.getUsedAt() != null) {
            throw new InvalidVerificationTokenException();
        }

        if (token.getExpiresAt().isBefore(OffsetDateTime.now())) {
            throw new ExpiredVerificationTokenException();
        }

        return token;
    }

    private VerificationToken getLatestValidTokenForEmail(
            String email,
            VerificationTokenType tokenType
    ) {
        if (email == null || email.isBlank()) {
            throw invalidTokenFor(tokenType);
        }

        User user = userRepository.findByEmail(normalizeEmail(email))
                .orElseThrow(() -> invalidTokenFor(tokenType));

        return verificationTokenRepository
                .findByUserIdAndTokenTypeAndUsedAtIsNullAndExpiresAtAfter(
                        user.getId(),
                        tokenType,
                        OffsetDateTime.now()
                )
                .orElseThrow(() -> invalidTokenFor(tokenType));
    }

    private RuntimeException invalidTokenFor(VerificationTokenType tokenType) {
        return tokenType == VerificationTokenType.PASSWORD_RESET
                ? new InvalidPasswordResetTokenException()
                : new InvalidVerificationTokenException();
    }

    private String exposedVerificationToken(String rawToken) {
        if (returnResetTokenForTesting && !demoVerificationCode.isEmpty()) {
            return demoVerificationCode;
        }
        return returnResetTokenForTesting ? rawToken : null;
    }

    private boolean isDemoVerificationCode(String token) {
        return returnResetTokenForTesting
                && !demoVerificationCode.isEmpty()
                && demoVerificationCode.equals(token);
    }

    private String normalizeEmail(String email) {
        return email == null ? null : email.trim().toLowerCase();
    }

    private String generateRawToken() {
        byte[] tokenBytes = new byte[TOKEN_BYTES];
        secureRandom.nextBytes(tokenBytes);
        return HexFormat.of().formatHex(tokenBytes);
    }

    private String hashToken(String rawToken) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] hashBytes = digest.digest(rawToken.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(hashBytes);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 algorithm is not available", e);
        }
    }
}
