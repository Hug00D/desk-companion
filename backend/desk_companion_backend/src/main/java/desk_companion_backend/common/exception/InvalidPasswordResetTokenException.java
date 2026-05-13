package desk_companion_backend.common.exception;

import org.springframework.http.HttpStatus;

public class InvalidPasswordResetTokenException extends BusinessException {
    public InvalidPasswordResetTokenException() {
        super("INVALID_PASSWORD_RESET_TOKEN", "Password reset token is invalid.", HttpStatus.BAD_REQUEST);
    }
}
