package desk_companion_backend.common.exception;

import org.springframework.http.HttpStatus;

public class InvalidGoogleTokenException extends BusinessException {
    public InvalidGoogleTokenException() {
        super("INVALID_GOOGLE_TOKEN", "Invalid Google ID token.", HttpStatus.UNAUTHORIZED);
    }
}