package desk_companion_backend.common.exception;

import org.springframework.http.HttpStatus;

public class AccountDeletedException extends BusinessException {
    public AccountDeletedException() {
        super("ACCOUNT_DELETED", "This account is deleted.", HttpStatus.FORBIDDEN);
    }
}