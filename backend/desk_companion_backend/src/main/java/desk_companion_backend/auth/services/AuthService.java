package desk_companion_backend.auth.service;

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

public interface AuthService {
    AuthResponse login(LoginRequest request);

    ForgotPasswordResponse forgotPassword(ForgotPasswordRequest request);

    ActionResponse resetPassword(ResetPasswordRequest request);

    AccountRecoveryResponse requestAccountRecovery(RequestAccountRecoveryRequest request);

    ConfirmAccountRecoveryResponse confirmAccountRecovery(ConfirmAccountRecoveryRequest request);

    ValidateResetTokenResponse validateResetToken(ValidateResetTokenRequest request);
}
