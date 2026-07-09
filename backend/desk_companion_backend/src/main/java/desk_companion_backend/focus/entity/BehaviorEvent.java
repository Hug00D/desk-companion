package desk_companion_backend.focus.entity;

import desk_companion_backend.user.entity.User;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.OffsetDateTime;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

@Entity
@Table(name = "behavior_events")
public class BehaviorEvent {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id", nullable = false, updatable = false)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id", nullable = false)
    private User user;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "session_id")
    private FocusSession session;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "round_id")
    private FocusRound round;

    @Column(name = "client_event_id")
    private UUID clientEventId;

    @Column(name = "related_event_id")
    private Long relatedEventId;

    @Column(name = "ts", nullable = false)
    private OffsetDateTime ts;

    @Column(name = "source", nullable = false)
    private String source = "vision";

    @Column(name = "event_type", nullable = false)
    private String eventType;

    @Column(name = "severity", nullable = false)
    private String severity = "info";

    @Column(name = "phase", nullable = false)
    private String phase = "point";

    @Column(name = "duration_ms")
    private Integer durationMs;

    @Column(name = "detected_object")
    private String detectedObject;

    @Column(name = "confidence_score")
    private Double confidenceScore;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "signals", columnDefinition = "jsonb", nullable = false)
    private Map<String, Object> signals = new HashMap<>();

    @Column(name = "action_triggered")
    private String actionTriggered;

    @Column(name = "outcome", nullable = false)
    private String outcome = "observed";

    @Column(name = "debug_snapshot_path")
    private String debugSnapshotPath;

    @Column(name = "schema_version", nullable = false)
    private int schemaVersion = 1;

    @Column(name = "created_at", nullable = false, updatable = false)
    private OffsetDateTime createdAt;

    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt;

    @PrePersist
    public void prePersist() {
        OffsetDateTime now = OffsetDateTime.now();
        if (ts == null) {
            ts = now;
        }
        if (source == null || source.isBlank()) {
            source = "vision";
        }
        if (severity == null || severity.isBlank()) {
            severity = "info";
        }
        if (phase == null || phase.isBlank()) {
            phase = "point";
        }
        if (outcome == null || outcome.isBlank()) {
            outcome = "observed";
        }
        if (signals == null) {
            signals = new HashMap<>();
        }
        if (schemaVersion <= 0) {
            schemaVersion = 1;
        }
        if (createdAt == null) {
            createdAt = now;
        }
        if (updatedAt == null) {
            updatedAt = now;
        }
    }

    @PreUpdate
    public void preUpdate() {
        updatedAt = OffsetDateTime.now();
    }

    public Long getId() {
        return id;
    }

    public User getUser() {
        return user;
    }

    public void setUser(User user) {
        this.user = user;
    }

    public FocusSession getSession() {
        return session;
    }

    public void setSession(FocusSession session) {
        this.session = session;
    }

    public FocusRound getRound() {
        return round;
    }

    public void setRound(FocusRound round) {
        this.round = round;
    }

    public UUID getClientEventId() {
        return clientEventId;
    }

    public void setClientEventId(UUID clientEventId) {
        this.clientEventId = clientEventId;
    }

    public Long getRelatedEventId() {
        return relatedEventId;
    }

    public void setRelatedEventId(Long relatedEventId) {
        this.relatedEventId = relatedEventId;
    }

    public OffsetDateTime getTs() {
        return ts;
    }

    public void setTs(OffsetDateTime ts) {
        this.ts = ts;
    }

    public String getSource() {
        return source;
    }

    public void setSource(String source) {
        this.source = source;
    }

    public String getEventType() {
        return eventType;
    }

    public void setEventType(String eventType) {
        this.eventType = eventType;
    }

    public String getSeverity() {
        return severity;
    }

    public void setSeverity(String severity) {
        this.severity = severity;
    }

    public String getPhase() {
        return phase;
    }

    public void setPhase(String phase) {
        this.phase = phase;
    }

    public Integer getDurationMs() {
        return durationMs;
    }

    public void setDurationMs(Integer durationMs) {
        this.durationMs = durationMs;
    }

    public String getDetectedObject() {
        return detectedObject;
    }

    public void setDetectedObject(String detectedObject) {
        this.detectedObject = detectedObject;
    }

    public Double getConfidenceScore() {
        return confidenceScore;
    }

    public void setConfidenceScore(Double confidenceScore) {
        this.confidenceScore = confidenceScore;
    }

    public Map<String, Object> getSignals() {
        return signals;
    }

    public void setSignals(Map<String, Object> signals) {
        this.signals = signals;
    }

    public String getActionTriggered() {
        return actionTriggered;
    }

    public void setActionTriggered(String actionTriggered) {
        this.actionTriggered = actionTriggered;
    }

    public String getOutcome() {
        return outcome;
    }

    public void setOutcome(String outcome) {
        this.outcome = outcome;
    }

    public String getDebugSnapshotPath() {
        return debugSnapshotPath;
    }

    public void setDebugSnapshotPath(String debugSnapshotPath) {
        this.debugSnapshotPath = debugSnapshotPath;
    }

    public int getSchemaVersion() {
        return schemaVersion;
    }

    public void setSchemaVersion(int schemaVersion) {
        this.schemaVersion = schemaVersion;
    }

    public OffsetDateTime getCreatedAt() {
        return createdAt;
    }

    public OffsetDateTime getUpdatedAt() {
        return updatedAt;
    }
}
