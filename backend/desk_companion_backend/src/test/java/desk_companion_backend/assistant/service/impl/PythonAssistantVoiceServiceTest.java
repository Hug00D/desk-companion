package desk_companion_backend.assistant.service.impl;

import desk_companion_backend.assistant.config.AssistantVoiceProperties;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpMethod;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

import java.nio.charset.StandardCharsets;
import java.util.Base64;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.method;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

class PythonAssistantVoiceServiceTest {

    @Test
    void synthesizesAndBundlesDownloadedWav() {
        var properties = new AssistantVoiceProperties();
        properties.setBaseUrl("http://voice.test");
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        byte[] wav = minimalWav();

        server.expect(requestTo("http://voice.test/tts"))
                .andExpect(method(HttpMethod.POST))
                .andRespond(withSuccess(
                        """
                        {"ok":true,"requestId":"voice-123","mode":"gpt_sovits",\
                        "audioUrl":"/audio/voice-123.wav","durationMs":4660}
                        """,
                        MediaType.APPLICATION_JSON
                ));
        server.expect(requestTo("http://voice.test/audio/voice-123.wav"))
                .andExpect(method(HttpMethod.GET))
                .andRespond(withSuccess(wav, MediaType.parseMediaType("audio/wav")));

        var service = new PythonAssistantVoiceService(properties, builder.build());
        var result = service.synthesize("你好，我是路米娜。");

        assertThat(result).isPresent();
        assertThat(result.orElseThrow().requestId()).isEqualTo("voice-123");
        assertThat(result.orElseThrow().durationMs()).isEqualTo(4660);
        assertThat(Base64.getDecoder().decode(result.orElseThrow().base64()))
                .isEqualTo(wav);
        server.verify();
    }

    @Test
    void fallsBackToTextWhenVoiceServiceIsUnavailable() {
        var properties = new AssistantVoiceProperties();
        properties.setBaseUrl("http://voice.test");
        RestClient.Builder builder = RestClient.builder();
        MockRestServiceServer server = MockRestServiceServer.bindTo(builder).build();
        server.expect(requestTo("http://voice.test/tts"))
                .andRespond(request -> {
                    throw new java.io.IOException("voice offline");
                });

        var service = new PythonAssistantVoiceService(properties, builder.build());

        assertThat(service.synthesize("仍然要回文字")).isEmpty();
        server.verify();
    }

    private byte[] minimalWav() {
        byte[] wav = new byte[44];
        System.arraycopy("RIFF".getBytes(StandardCharsets.US_ASCII), 0, wav, 0, 4);
        System.arraycopy("WAVE".getBytes(StandardCharsets.US_ASCII), 0, wav, 8, 4);
        return wav;
    }
}
