package desk_companion_backend.common.exception;

import org.springframework.http.HttpStatus;

public class InvalidPasswordException extends BusinessException {
    public InvalidPasswordException(String problem) {
        super("INVALID_PASSWORD_RESET", problem, HttpStatus.BAD_REQUEST);
    }
}
