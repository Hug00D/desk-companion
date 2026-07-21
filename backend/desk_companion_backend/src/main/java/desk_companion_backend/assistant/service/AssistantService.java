package desk_companion_backend.assistant.service;

import desk_companion_backend.assistant.dto.AssistantChatRequest;
import desk_companion_backend.assistant.dto.AssistantChatResponse;
import desk_companion_backend.assistant.dto.AssistantDecideRequest;
import desk_companion_backend.assistant.dto.AssistantDecideResponse;

public interface AssistantService {

    AssistantChatResponse chat(AssistantChatRequest request);

    AssistantDecideResponse decide(AssistantDecideRequest request);
}
