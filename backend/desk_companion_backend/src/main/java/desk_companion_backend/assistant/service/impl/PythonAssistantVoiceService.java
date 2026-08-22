package desk_companion_backend.assistant.service.impl;

import desk_companion_backend.assistant.config.AssistantVoiceProperties;
import desk_companion_backend.assistant.dto.AssistantAudioResponse;
import desk_companion_backend.assistant.service.AssistantVoiceService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

import java.time.Duration;
import java.net.URI;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

@Service
public class PythonAssistantVoiceService implements AssistantVoiceService {

    private static final Logger log = LoggerFactory.getLogger(PythonAssistantVoiceService.class);

    private record TtsResponse(
            Boolean ok,
            String requestId,
            String mode,
            String audioUrl,
            Long durationMs
    ) {
    }

    private final AssistantVoiceProperties properties;
    private final RestClient restClient;

    public PythonAssistantVoiceService(
            AssistantVoiceProperties properties,
            RestClient.Builder restClientBuilder
    ) {
        this.properties = properties;
        var requestFactory = new SimpleClientHttpRequestFactory();
        requestFactory.setConnectTimeout(Duration.ofSeconds(
                Math.max(1, properties.getConnectTimeoutSeconds())
        ));
        requestFactory.setReadTimeout(Duration.ofSeconds(
                Math.max(1, properties.getRequestTimeoutSeconds())
        ));
        this.restClient = restClientBuilder
                .baseUrl(properties.getBaseUrl())
                .requestFactory(requestFactory)
                .build();
    }

    PythonAssistantVoiceService(
            AssistantVoiceProperties properties,
            RestClient restClient
    ) {
        this.properties = properties;
        this.restClient = restClient;
    }

    @Override
    public Optional<AssistantAudioResponse> synthesize(String text) {
        if (!properties.isEnabled() || text == null || text.isBlank()) {
            return Optional.empty();
        }

        String requestId = "assistant-backend-" + UUID.randomUUID();
        Map<String, Object> request = new LinkedHashMap<>();
        request.put("requestId", requestId);
        request.put("text", text);
        request.put("source", "assistant");
        request.put("status", "assistant_chat");
        request.put("eventType", "assistant.chat_reply");

        try {
            TtsResponse tts = restClient.post()
                    .uri(resolveUri("/tts"))
                    .contentType(MediaType.APPLICATION_JSON)
                    .body(request)
                    .retrieve()
                    .body(TtsResponse.class);
            if (tts == null || !Boolean.TRUE.equals(tts.ok()) || tts.audioUrl() == null) {
                log.warn("Voice service returned no generated audio for request {}", requestId);
                return Optional.empty();
            }

            ResponseEntity<byte[]> audioResponse = restClient.get()
                    .uri(resolveUri(tts.audioUrl()))
                    .retrieve()
                    .toEntity(byte[].class);
            byte[] audio = audioResponse.getBody();
            if (!isCompleteWav(audio)) {
                log.warn("Voice service returned an invalid WAV for request {}", requestId);
                return Optional.empty();
            }

            String contentType = Optional.ofNullable(audioResponse.getHeaders().getContentType())
                    .map(MediaType::toString)
                    .orElse("audio/wav");
            return Optional.of(new AssistantAudioResponse(
                    tts.requestId() == null ? requestId : tts.requestId(),
                    contentType,
                    Base64.getEncoder().encodeToString(audio),
                    tts.durationMs()
            ));
        } catch (RestClientException | IllegalArgumentException ex) {
            // TTS is an enhancement. Preserve the AI text response when the
            // separate voice service is stopped, busy, or temporarily offline.
            log.warn("Assistant voice synthesis unavailable at {}: {}",
                    properties.getBaseUrl(), ex.getMessage());
            return Optional.empty();
        }
    }

    private boolean isCompleteWav(byte[] audio) {
        return audio != null
                && audio.length >= 44
                && audio[0] == 'R'
                && audio[1] == 'I'
                && audio[2] == 'F'
                && audio[3] == 'F'
                && audio[8] == 'W'
                && audio[9] == 'A'
                && audio[10] == 'V'
                && audio[11] == 'E';
    }

    private URI resolveUri(String pathOrUrl) {
        URI value = URI.create(pathOrUrl);
        if (value.isAbsolute()) {
            return value;
        }
        String baseUrl = properties.getBaseUrl().endsWith("/")
                ? properties.getBaseUrl()
                : properties.getBaseUrl() + "/";
        String relativePath = pathOrUrl.startsWith("/")
                ? pathOrUrl.substring(1)
                : pathOrUrl;
        return URI.create(baseUrl).resolve(relativePath);
    }
}
