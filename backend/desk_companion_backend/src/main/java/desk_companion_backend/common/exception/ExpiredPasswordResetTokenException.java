package desk_companion_backend.common.exception;

import org.springframework.http.HttpStatus;

public class ExpiredPasswordResetTokenException extends BusinessException {
    public ExpiredPasswordResetTokenException() {
        super("EXPIRED_PASSWORD_RESET_TOKEN", "Password reset token is expired.", HttpStatus.BAD_REQUEST);
    }
}
