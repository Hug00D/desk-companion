package desk_companion_backend.common.exception;

import org.springframework.http.HttpStatus;

public class AssistantUnavailableException extends BusinessException {
    public AssistantUnavailableException() {
        super("ASSISTANT_UNAVAILABLE", "Assistant service is temporarily unavailable.", HttpStatus.BAD_GATEWAY);
    }

    public AssistantUnavailableException(String message) {
        super("ASSISTANT_UNAVAILABLE", message, HttpStatus.BAD_GATEWAY);
    }
}
