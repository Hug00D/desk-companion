package desk_companion_backend.common.exception;

import org.springframework.http.HttpStatus;

public class InvalidVerificationTokenException extends BusinessException {
    public InvalidVerificationTokenException() {
        super("INVALID_VERIFICATION_TOKEN", "Verification token is invalid.", HttpStatus.BAD_REQUEST);
    }
}
