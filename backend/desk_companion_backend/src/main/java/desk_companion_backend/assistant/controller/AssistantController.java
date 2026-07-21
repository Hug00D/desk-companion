package desk_companion_backend.assistant.controller;

import desk_companion_backend.assistant.dto.AssistantChatRequest;
import desk_companion_backend.assistant.dto.AssistantChatResponse;
import desk_companion_backend.assistant.dto.AssistantDecideRequest;
import desk_companion_backend.assistant.dto.AssistantDecideResponse;
import desk_companion_backend.assistant.service.AssistantService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/assistant")
public class AssistantController {

    private final AssistantService assistantService;

    public AssistantController(AssistantService assistantService) {
        this.assistantService = assistantService;
    }

    @PostMapping("/chat")
    public AssistantChatResponse chat(@Valid @RequestBody AssistantChatRequest request) {
        return assistantService.chat(request);
    }

    @PostMapping("/decide")
    public AssistantDecideResponse decide(@Valid @RequestBody AssistantDecideRequest request) {
        return assistantService.decide(request);
    }
}
