package desk_companion_backend.common.exception;

import org.springframework.http.HttpStatus;

public class InvalidAccountStatusException extends BusinessException {
    public InvalidAccountStatusException(String status) {
        super("INVALID_ACCOUNT_STATUS", "Unsupported account status: " + status, HttpStatus.BAD_REQUEST);
    }
}