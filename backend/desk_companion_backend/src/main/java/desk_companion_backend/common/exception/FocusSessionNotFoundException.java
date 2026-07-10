package desk_companion_backend.common.exception;

import org.springframework.http.HttpStatus;

public class FocusSessionNotFoundException extends BusinessException {

    public FocusSessionNotFoundException() {
        super("FOCUS_SESSION_NOT_FOUND", "Focus session was not found.", HttpStatus.NOT_FOUND);
    }
}
