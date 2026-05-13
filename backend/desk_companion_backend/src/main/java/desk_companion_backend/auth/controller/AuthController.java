package desk_companion_backend.auth.controller;

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
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/auth")
public class AuthController {

    private final AuthService authService;

    public AuthController(AuthService authService) {
        this.authService = authService;
    }

    @PostMapping("/login")
    public AuthResponse login(@Valid @RequestBody LoginRequest request) {
        return authService.login(request);
    }

    @PostMapping("/forgot-password")
    public ForgotPasswordResponse forgotPassword(@Valid @RequestBody ForgotPasswordRequest request) {
        return authService.forgotPassword(request);
    }

    @PostMapping("/reset-password")
    public ActionResponse resetPassword(@Valid @RequestBody ResetPasswordRequest request) {
        return authService.resetPassword(request);
    }

    @PostMapping("/account-recovery")
    public AccountRecoveryResponse requestAccountRecovery(@Valid @RequestBody RequestAccountRecoveryRequest request) {
        return authService.requestAccountRecovery(request);
    }

    @PostMapping("/account-recovery/confirm")
    public ConfirmAccountRecoveryResponse confirmAccountRecovery(
            @Valid @RequestBody ConfirmAccountRecoveryRequest request
    ) {
        return authService.confirmAccountRecovery(request);
    }

    @PostMapping("/validate-reset-token")
    public ValidateResetTokenResponse validateResetToken(@Valid @RequestBody ValidateResetTokenRequest request) {
        return authService.validateResetToken(request);
    }
}
