package desk_companion_backend.common.exception;

import org.springframework.http.HttpStatus;

public class EmailAlreadyExistsException extends BusinessException {
    public EmailAlreadyExistsException(String email) {
        super("EMAIL_ALREADY_EXISTS", "Email already exists: " + email, HttpStatus.CONFLICT);
    }
}