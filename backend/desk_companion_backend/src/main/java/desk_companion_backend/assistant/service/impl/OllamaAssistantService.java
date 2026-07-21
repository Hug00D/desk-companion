package desk_companion_backend.assistant.service.impl;

import desk_companion_backend.assistant.config.AssistantProperties;
import desk_companion_backend.assistant.dto.AssistantChatRequest;
import desk_companion_backend.assistant.dto.AssistantChatResponse;
import desk_companion_backend.assistant.dto.AssistantDecideRequest;
import desk_companion_backend.assistant.dto.AssistantDecideResponse;
import desk_companion_backend.assistant.dto.AssistantMessage;
import desk_companion_backend.assistant.dto.OllamaChatRequest;
import desk_companion_backend.assistant.dto.OllamaChatResponse;
import desk_companion_backend.assistant.service.AssistantService;
import desk_companion_backend.common.exception.AssistantDecisionParseException;
import desk_companion_backend.common.exception.AssistantUnavailableException;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

import java.time.Duration;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

@Service
public class OllamaAssistantService implements AssistantService {

    // Phase 1 only verifies the backend-to-Ollama chat pipeline.
    // Tool calling is intentionally disabled here; Phase 2 will add a separate
    // low-temperature intent/tool decision before executing app actions.
    private static final String SYSTEM_PROMPT = """
            You are Desk Companion's in-app assistant.
            Reply in the user's language.
            This phase is chat-only: do not claim that you already executed app actions.
            If the user asks for an app action, explain briefly that the app action pipeline is being connected and answer helpfully.
            Keep replies concise but complete. Use at most two short paragraphs.
            """;

    // Keep both this prompt and the output contract tiny: the shared GPU
    // evaluates prompt tokens at ~11/s and generates at under 1/s, so every
    // extra token here directly extends decide() latency. The model only
    // classifies; confirmation policy, confirmation text and chat wording are
    // filled in by the backend afterwards (see expandDecision).
    private static final String DECIDE_SYSTEM_PROMPT = """
            Classify the user's message for the Desk Companion app.
            Reply with compact JSON only, exactly these keys:
            {"mode":"action|clarify|chat","intent":<string or null>,"confidence":<0..1>,"minutes":<int or null>}
            Intents: start_pomodoro, pause_pomodoro, resume_pomodoro, stop_pomodoro,
            show_focus_summary, show_timer_status, request_break, report_tired, report_distracted.
            Rules:
            - mode action: exactly one clear supported intent, else use mode clarify.
            - mode chat: the user only wants conversation. intent must be null.
            - minutes: only for start_pomodoro when the user names a duration.
            """;

    private static final String DECIDE_FORMAT = "json";
    private static final List<String> SUPPORTED_INTENTS = List.of(
            "start_pomodoro",
            "pause_pomodoro",
            "resume_pomodoro",
            "stop_pomodoro",
            "show_focus_summary",
            "show_timer_status",
            "request_break",
            "report_tired",
            "report_distracted"
    );

    // State-changing intents always ask the user before running, matching the
    // pending-action confirm flow on the Flutter side.
    private static final Set<String> CONFIRMATION_REQUIRED_INTENTS = Set.of(
            "start_pomodoro",
            "pause_pomodoro",
            "resume_pomodoro",
            "stop_pomodoro",
            "request_break"
    );

    private static final String CLARIFY_QUESTION =
            "你是想執行功能、換個說法，還是單純聊聊呢？";

    private record SlimDecision(String mode, String intent, Double confidence, Integer minutes) {
    }

    private final AssistantProperties properties;
    private final RestClient chatRestClient;
    private final RestClient decideRestClient;
    private final ObjectMapper objectMapper;

    public OllamaAssistantService(
            AssistantProperties properties,
            RestClient.Builder restClientBuilder,
            ObjectMapper objectMapper
    ) {
        this.properties = properties;
        this.chatRestClient = restClientBuilder
                .baseUrl(properties.getOllamaBaseUrl())
                .requestFactory(buildRequestFactory(properties.getRequestTimeoutSeconds()))
                .build();
        this.decideRestClient = restClientBuilder
                .baseUrl(properties.getOllamaBaseUrl())
                .requestFactory(buildRequestFactory(properties.getDecideTimeoutSeconds()))
                .build();
        this.objectMapper = objectMapper;
    }

    @Override
    public AssistantChatResponse chat(AssistantChatRequest request) {
        OllamaChatResponse response;
        try {
            // Ollama is reached through the configured base URL. In local
            // development this usually points at the SSH tunnel on localhost.
            response = chatRestClient.post()
                    .uri("/api/chat")
                    .body(buildOllamaRequest(request))
                    .retrieve()
                    .body(OllamaChatResponse.class);
        } catch (RestClientException ex) {
            throw new AssistantUnavailableException(
                    "Assistant service is temporarily unavailable. Ollama target: "
                            + properties.getOllamaBaseUrl()
                            + ", model: "
                            + properties.getModel()
                            + ". Cause: "
                            + ex.getClass().getSimpleName()
            );
        }

        String reply = "";
        if (response != null && response.message() != null && response.message().content() != null) {
            reply = response.message().content().trim();
        }

        return new AssistantChatResponse(
                // Keep the response contract compatible with the planned
                // action/chat/clarify flow, even though Phase 1 always returns chat.
                "chat",
                reply,
                null,
                null,
                response != null && response.model() != null ? response.model() : properties.getModel()
        );
    }

    @Override
    public AssistantDecideResponse decide(AssistantDecideRequest request) {
        AssistantDecideResponse ruleDecision = decideWithLocalRules(request);
        if (ruleDecision != null) {
            return ruleDecision;
        }

        OllamaChatResponse response;
        try {
            response = decideRestClient.post()
                    .uri("/api/chat")
                    .body(buildOllamaDecideRequest(request))
                    .retrieve()
                    .body(OllamaChatResponse.class);
        } catch (RestClientException ex) {
            throw new AssistantUnavailableException(
                    "Assistant decide service is temporarily unavailable. Ollama target: "
                            + properties.getOllamaBaseUrl()
                            + ", model: "
                            + properties.getModel()
                            + ". Cause: "
                            + ex.getClass().getSimpleName()
            );
        }

        String content = "";
        if (response != null && response.message() != null && response.message().content() != null) {
            content = response.message().content().trim();
        }

        SlimDecision decision = parseDecision(content);
        validateDecision(decision, content);
        return expandDecision(decision, request, response);
    }

    private AssistantDecideResponse expandDecision(
            SlimDecision decision,
            AssistantDecideRequest request,
            OllamaChatResponse response
    ) {
        String model = response != null && response.model() != null ? response.model() : properties.getModel();
        double confidence = decision.confidence() == null
                ? 0.5
                : Math.min(1, Math.max(0, decision.confidence()));

        return switch (decision.mode()) {
            case "action" -> {
                Map<String, Object> parameters = decision.minutes() == null
                        ? Map.of()
                        : Map.of("durationMinutes", decision.minutes());
                yield new AssistantDecideResponse(
                        "action",
                        decision.intent(),
                        confidence,
                        CONFIRMATION_REQUIRED_INTENTS.contains(decision.intent()),
                        confirmationTextFor(decision.intent(), parameters),
                        null,
                        parameters,
                        model
                );
            }
            case "clarify" -> new AssistantDecideResponse(
                    "clarify",
                    null,
                    confidence,
                    true,
                    CLARIFY_QUESTION,
                    null,
                    Map.of(),
                    model
            );
            // chat: reuse the chat pipeline for the wording so the decision
            // output itself stays tiny.
            default -> {
                AssistantChatResponse chatResponse = chat(new AssistantChatRequest(
                        request.message(),
                        request.history(),
                        request.context()
                ));
                yield new AssistantDecideResponse(
                        "chat",
                        null,
                        confidence,
                        false,
                        null,
                        chatResponse.message(),
                        Map.of(),
                        model
                );
            }
        };
    }

    private AssistantDecideResponse decideWithLocalRules(AssistantDecideRequest request) {
        String text = normalize(request.message());
        Integer durationMinutes = extractDurationMinutes(text);

        if (containsAny(text, "\u505c\u6b62", "\u4e2d\u6b62", "\u95dc\u6389", "\u53d6\u6d88")) {
            return actionDecision("stop_pomodoro", 0.92, null);
        }
        if (containsAny(text, "\u66ab\u505c", "\u505c\u4e00\u4e0b", "\u5148\u7b49\u4e00\u4e0b")) {
            return actionDecision("pause_pomodoro", 0.9, null);
        }
        if (containsAny(text, "\u7e7c\u7e8c", "\u6062\u5fa9", "\u63a5\u8457", "\u56de\u4f86\u4e86")) {
            return actionDecision("resume_pomodoro", 0.9, null);
        }
        if (containsAny(text, "\u5269\u591a\u4e45", "\u9084\u5269", "\u5269\u5e7e\u5206")) {
            return actionDecision("show_timer_status", 0.9, null);
        }
        if (containsAny(text, "\u6458\u8981", "\u7d71\u8a08", "\u5c08\u6ce8\u72c0\u614b", "\u505a\u5e7e\u8f2a", "\u5e7e\u8f2a")) {
            return actionDecision("show_focus_summary", 0.86, null);
        }
        if (containsAny(text, "\u6211\u7d2f\u4e86", "\u6709\u9ede\u7d2f", "\u597d\u7d2f", "\u773c\u775b\u9178")) {
            return actionDecision("report_tired", 0.86, null);
        }
        if (containsAny(text, "\u5206\u5fc3", "\u96e3\u4ee5\u5c08\u5fc3", "\u4e0d\u592a\u80fd\u5c08\u5fc3")) {
            return actionDecision("report_distracted", 0.84, null);
        }
        if (containsAny(text, "\u60f3\u4f11\u606f", "\u8b93\u6211\u4f11\u606f", "\u4f11\u606f\u4e00\u4e0b")) {
            return actionDecision("request_break", 0.88, null);
        }
        if (containsAny(text, "\u756a\u8304\u9418", "\u5c08\u6ce8\u9418") &&
                containsAny(text, "\u958b", "\u958b\u59cb", "\u5e6b\u6211", "\u8a2d\u5b9a")) {
            Map<String, Object> parameters = new LinkedHashMap<>();
            if (durationMinutes != null) {
                parameters.put("durationMinutes", durationMinutes);
            }
            return actionDecision("start_pomodoro", 0.93, parameters);
        }
        // Only clear-cut action commands are short-circuited here. Chat-leaning
        // or ambiguous input falls through to the model on purpose: canned
        // replies for conversation feel robotic, and clarify-vs-chat is
        // exactly the judgement the model is for.
        return null;
    }

    private AssistantDecideResponse actionDecision(
            String intent,
            double confidence,
            Map<String, Object> parameters
    ) {
        return new AssistantDecideResponse(
                "action",
                intent,
                confidence,
                false,
                confirmationTextFor(intent, parameters),
                null,
                parameters == null ? Map.of() : parameters,
                properties.getModel()
        );
    }

    private String confirmationTextFor(String intent, Map<String, Object> parameters) {
        if ("start_pomodoro".equals(intent)) {
            Object minutes = parameters == null ? null : parameters.get("durationMinutes");
            return minutes == null
                    ? "\u597d\u7684\uff0c\u6211\u5e6b\u4f60\u958b\u59cb\u756a\u8304\u9418\u3002"
                    : "\u597d\u7684\uff0c\u6211\u5e6b\u4f60\u958b\u59cb " + minutes + " \u5206\u9418\u756a\u8304\u9418\u3002";
        }
        return switch (intent) {
            case "pause_pomodoro" -> "\u597d\u7684\uff0c\u6211\u5e6b\u4f60\u66ab\u505c\u756a\u8304\u9418\u3002";
            case "resume_pomodoro" -> "\u597d\u7684\uff0c\u6211\u5e6b\u4f60\u7e7c\u7e8c\u756a\u8304\u9418\u3002";
            case "stop_pomodoro" -> "\u597d\u7684\uff0c\u6211\u5e6b\u4f60\u505c\u6b62\u756a\u8304\u9418\u3002";
            case "show_focus_summary" -> "\u597d\u7684\uff0c\u6211\u5e6b\u4f60\u67e5\u770b\u5c08\u6ce8\u7d71\u8a08\u3002";
            case "show_timer_status" -> "\u597d\u7684\uff0c\u6211\u5e6b\u4f60\u67e5\u770b\u756a\u8304\u9418\u72c0\u614b\u3002";
            case "request_break" -> "\u597d\u7684\uff0c\u5148\u4f11\u606f\u4e00\u4e0b\u3002";
            case "report_tired" -> "\u6211\u77e5\u9053\u4f60\u7d2f\u4e86\uff0c\u6211\u6703\u5e6b\u4f60\u8a18\u9304\u9019\u500b\u72c0\u614b\u3002";
            case "report_distracted" -> "\u6211\u77e5\u9053\u4f60\u5206\u5fc3\u4e86\uff0c\u6211\u6703\u5e6b\u4f60\u8a18\u9304\u9019\u500b\u72c0\u614b\u3002";
            default -> "\u597d\u7684\u3002";
        };
    }

    private String normalize(String value) {
        return value == null
                ? ""
                : value.toLowerCase().replaceAll("\\s+", "");
    }

    private boolean containsAny(String text, String... keywords) {
        for (String keyword : keywords) {
            if (text.contains(keyword)) {
                return true;
            }
        }
        return false;
    }

    private Integer extractDurationMinutes(String text) {
        var matcher = java.util.regex.Pattern.compile("(\\d{1,3})\\s*\u5206").matcher(text);
        if (matcher.find()) {
            return Integer.parseInt(matcher.group(1));
        }
        if (text.contains("\u4e8c\u5341\u4e94\u5206")) {
            return 25;
        }
        if (text.contains("\u5341\u4e94\u5206")) {
            return 15;
        }
        if (text.contains("\u4e94\u5206")) {
            return 5;
        }
        return null;
    }

    private OllamaChatRequest buildOllamaRequest(AssistantChatRequest request) {
        List<AssistantMessage> messages = new ArrayList<>();
        messages.add(new AssistantMessage("system", buildSystemPrompt(request.context())));
        if (request.history() != null) {
            messages.addAll(request.history());
        }
        messages.add(new AssistantMessage("user", request.message()));

        Map<String, Object> options = new LinkedHashMap<>();
        // Keep num_predict small while using the shared GPU server. A large
        // value can make REST Client look stuck even when the tunnel is healthy.
        options.put("temperature", properties.getChatTemperature());
        options.put("num_predict", properties.getChatNumPredict());

        return new OllamaChatRequest(
                properties.getModel(),
                messages,
                false,
                options,
                null
        );
    }

    private OllamaChatRequest buildOllamaDecideRequest(AssistantDecideRequest request) {
        List<AssistantMessage> messages = new ArrayList<>();
        messages.add(new AssistantMessage("system", buildDecideSystemPrompt(request.context())));
        if (request.history() != null) {
            messages.addAll(request.history());
        }
        messages.add(new AssistantMessage("user", request.message()));

        Map<String, Object> options = new LinkedHashMap<>();
        options.put("temperature", properties.getDecideTemperature());
        options.put("num_predict", properties.getDecideNumPredict());

        return new OllamaChatRequest(
                properties.getModel(),
                messages,
                false,
                options,
                DECIDE_FORMAT
        );
    }

    private String buildSystemPrompt(Map<String, Object> context) {
        if (context == null || context.isEmpty()) {
            return SYSTEM_PROMPT;
        }
        return SYSTEM_PROMPT + "\nCurrent app context: " + context;
    }

    private String buildDecideSystemPrompt(Map<String, Object> context) {
        if (context == null || context.isEmpty()) {
            return DECIDE_SYSTEM_PROMPT;
        }
        return DECIDE_SYSTEM_PROMPT + "\nCurrent app context: " + context;
    }

    private SlimDecision parseDecision(String content) {
        if (content.isBlank()) {
            throw new AssistantDecisionParseException("Ollama returned an empty decision response.");
        }

        try {
            var node = objectMapper.readTree(content);
            String intent = node.hasNonNull("intent") ? node.get("intent").asText() : null;
            if (intent != null && (intent.isBlank() || "null".equals(intent) || "none".equals(intent))) {
                intent = null;
            }
            return new SlimDecision(
                    node.hasNonNull("mode") ? node.get("mode").asText() : null,
                    intent,
                    node.hasNonNull("confidence") ? node.get("confidence").asDouble() : null,
                    node.hasNonNull("minutes") ? node.get("minutes").asInt() : null
            );
        } catch (JsonProcessingException ex) {
            throw new AssistantDecisionParseException(
                    "Ollama decision response was not valid JSON. Raw response: " + content
            );
        }
    }

    private void validateDecision(SlimDecision decision, String rawContent) {
        if (decision.mode() == null || !List.of("action", "chat", "clarify").contains(decision.mode())) {
            throw new AssistantDecisionParseException("Ollama decision mode is invalid. Raw response: " + rawContent);
        }

        if ("action".equals(decision.mode())
                && (decision.intent() == null || !SUPPORTED_INTENTS.contains(decision.intent()))) {
            throw new AssistantDecisionParseException(
                    "Action decision is missing a supported intent. Raw response: " + rawContent);
        }
    }

    private SimpleClientHttpRequestFactory buildRequestFactory(Integer timeoutSeconds) {
        var requestFactory = new SimpleClientHttpRequestFactory();
        Duration timeout = Duration.ofSeconds(Math.max(1, timeoutSeconds));
        // Use bounded waits so the app gets a clear ASSISTANT_UNAVAILABLE error
        // instead of hanging forever when Ollama is busy or unreachable.
        requestFactory.setConnectTimeout(timeout);
        requestFactory.setReadTimeout(timeout);
        return requestFactory;
    }
}
