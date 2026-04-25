package desk_companion_backend.common.exception;

import org.springframework.http.HttpStatus;

public class AccountSuspendedException extends BusinessException {
    public AccountSuspendedException() {
        super("ACCOUNT_SUSPENDED", "This account is suspended.", HttpStatus.FORBIDDEN);
    }
}