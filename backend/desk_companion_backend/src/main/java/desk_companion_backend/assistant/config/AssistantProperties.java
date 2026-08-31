package desk_companion_backend.assistant.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "app.assistant")
public class AssistantProperties {

    private String ollamaBaseUrl = "http://localhost:11434";
    private String model = "qwen2.5:7b";
    private Double chatTemperature = 0.8;
    // Companion replies are intentionally brief by default. Detailed answers
    // are still possible when the user explicitly asks for them.
    private Integer chatNumPredict = 96;
    private Integer requestTimeoutSeconds = 60;
    private Double decideTemperature = 0.15;
    // The slim decide contract only needs ~35 tokens of JSON; 48 leaves margin.
    private Integer decideNumPredict = 48;
    private Integer decideTimeoutSeconds = 60;

    public String getOllamaBaseUrl() {
        return ollamaBaseUrl;
    }

    public void setOllamaBaseUrl(String ollamaBaseUrl) {
        this.ollamaBaseUrl = ollamaBaseUrl;
    }

    public String getModel() {
        return model;
    }

    public void setModel(String model) {
        this.model = model;
    }

    public Double getChatTemperature() {
        return chatTemperature;
    }

    public void setChatTemperature(Double chatTemperature) {
        this.chatTemperature = chatTemperature;
    }

    public Integer getChatNumPredict() {
        return chatNumPredict;
    }

    public void setChatNumPredict(Integer chatNumPredict) {
        this.chatNumPredict = chatNumPredict;
    }

    public Integer getRequestTimeoutSeconds() {
        return requestTimeoutSeconds;
    }

    public void setRequestTimeoutSeconds(Integer requestTimeoutSeconds) {
        this.requestTimeoutSeconds = requestTimeoutSeconds;
    }

    public Double getDecideTemperature() {
        return decideTemperature;
    }

    public void setDecideTemperature(Double decideTemperature) {
        this.decideTemperature = decideTemperature;
    }

    public Integer getDecideNumPredict() {
        return decideNumPredict;
    }

    public void setDecideNumPredict(Integer decideNumPredict) {
        this.decideNumPredict = decideNumPredict;
    }

    public Integer getDecideTimeoutSeconds() {
        return decideTimeoutSeconds;
    }

    public void setDecideTimeoutSeconds(Integer decideTimeoutSeconds) {
        this.decideTimeoutSeconds = decideTimeoutSeconds;
    }
}
