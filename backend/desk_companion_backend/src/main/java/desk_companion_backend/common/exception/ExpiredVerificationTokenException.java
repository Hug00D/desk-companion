package desk_companion_backend.common.exception;

import org.springframework.http.HttpStatus;

public class ExpiredVerificationTokenException extends BusinessException {
    public ExpiredVerificationTokenException() {
        super("EXPIRED_VERIFICATION_TOKEN", "Verification token is expired.", HttpStatus.BAD_REQUEST);
    }
}
