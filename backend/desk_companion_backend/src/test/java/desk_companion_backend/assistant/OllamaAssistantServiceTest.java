package desk_companion_backend.assistant;

import com.fasterxml.jackson.databind.ObjectMapper;
import desk_companion_backend.assistant.config.AssistantProperties;
import desk_companion_backend.assistant.dto.AssistantDecideRequest;
import desk_companion_backend.assistant.service.impl.OllamaAssistantService;
import org.junit.jupiter.api.Test;
import org.springframework.web.client.RestClient;

import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

class OllamaAssistantServiceTest {

    private final OllamaAssistantService service = new OllamaAssistantService(
            new AssistantProperties(),
            RestClient.builder(),
            new ObjectMapper()
    );

    @Test
    void decideReturnsActionForClearPomodoroRequest() {
        var response = service.decide(new AssistantDecideRequest(
                "幫我開一個 25 分鐘番茄鐘",
                null,
                null
        ));

        assertThat(response.mode()).isEqualTo("action");
        assertThat(response.intent()).isEqualTo("start_pomodoro");
        assertThat(response.needsConfirmation()).isTrue();
        assertThat(response.parameters()).containsEntry("durationMinutes", 25);
    }

    @Test
    void decideUsesLocalRulesForStartTimerRequest() {
        var response = service.decide(new AssistantDecideRequest(
                "\u958b\u59cb\u8a08\u6642",
                null,
                null
        ));

        assertThat(response.mode()).isEqualTo("action");
        assertThat(response.intent()).isEqualTo("start_pomodoro");
        assertThat(response.needsConfirmation()).isTrue();
    }

    @Test
    void decideReturnsClarifyForAmbiguousHelpRequest() {
        var response = service.decide(new AssistantDecideRequest(
                "幫我一下，我快不行了",
                null,
                Map.of("pomodoro", Map.of("status", "running"))
        ));

        assertThat(response.mode()).isEqualTo("clarify");
        assertThat(response.intent()).isNull();
        assertThat(response.needsConfirmation()).isTrue();
        assertThat(response.confirmationText()).isNotBlank();
    }

    @Test
    void decideReturnsChatForEncouragementRequest() {
        var response = service.decide(new AssistantDecideRequest(
                "我今天讀書有點挫折，可以鼓勵我一下嗎？",
                null,
                null
        ));

        assertThat(response.mode()).isEqualTo("chat");
        assertThat(response.intent()).isNull();
        assertThat(response.chatReply()).isNotBlank();
    }

    @Test
    void sanitizeChatReplyRemovesModelSeparatorArtifacts() {
        assertThat(OllamaAssistantService.sanitizeChatReply(
                "好 ==========================================================…"
        )).isEqualTo("好。");
    }

    @Test
    void sanitizeChatReplyRemovesHiddenReasoning() {
        assertThat(OllamaAssistantService.sanitizeChatReply(
                "<think>internal reasoning</think>我陪你聊點輕鬆的。"
        )).isEqualTo("我陪你聊點輕鬆的。");
    }
}
