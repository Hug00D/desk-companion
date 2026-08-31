package desk_companion_backend.common.exception;

import org.springframework.http.HttpStatus;

public class AssistantDecisionParseException extends BusinessException {
    public AssistantDecisionParseException(String message) {
        super("ASSISTANT_DECISION_PARSE_FAILED", message, HttpStatus.BAD_GATEWAY);
    }
}
