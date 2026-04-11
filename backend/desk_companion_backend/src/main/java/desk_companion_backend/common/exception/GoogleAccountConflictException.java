package desk_companion_backend.common.exception;

import org.springframework.http.HttpStatus;

public class GoogleAccountConflictException extends BusinessException {
    public GoogleAccountConflictException(String email) {
        super(
                "GOOGLE_ACCOUNT_CONFLICT",
                "This email is already registered with email/password. Please login with the original method and bind Google later: " + email,
                HttpStatus.CONFLICT
        );
    }
}