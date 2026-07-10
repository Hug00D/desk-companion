package desk_companion_backend.common.exception;

import org.springframework.http.HttpStatus;

public class FocusRoundNotFoundException extends BusinessException {

    public FocusRoundNotFoundException() {
        super("FOCUS_ROUND_NOT_FOUND", "Focus round was not found.", HttpStatus.NOT_FOUND);
    }
}
