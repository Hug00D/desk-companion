package desk_companion_backend.assistant.service;

import desk_companion_backend.assistant.dto.AssistantAudioResponse;

import java.util.Optional;

public interface AssistantVoiceService {

    Optional<AssistantAudioResponse> synthesize(String text);
}
