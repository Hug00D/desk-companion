package desk_companion_backend.focus.entity;

import desk_companion_backend.user.entity.User;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
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
@Table(name = "focus_sessions")
public class FocusSession {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id", nullable = false)
    private User user;

    @Column(name = "client_session_id")
    private UUID clientSessionId;

    @Column(name = "start_at", nullable = false)
    private OffsetDateTime startAt;

    @Column(name = "end_at")
    private OffsetDateTime endAt;

    @Column(name = "status", nullable = false)
    private String status = "active";

    @Column(name = "end_reason")
    private String endReason;

    @Column(name = "mode")
    private String mode;

    @Column(name = "timezone", nullable = false)
    private String timezone = "Asia/Taipei";

    @Column(name = "target_seconds")
    private Integer targetSeconds;

    @Column(name = "monitored_seconds", nullable = false)
    private int monitoredSeconds;

    @Column(name = "focus_seconds", nullable = false)
    private int focusSeconds;

    @Column(name = "distracted_seconds", nullable = false)
    private int distractedSeconds;

    @Column(name = "attention_seconds", nullable = false)
    private int attentionSeconds;

    @Column(name = "fatigue_seconds", nullable = false)
    private int fatigueSeconds;

    @Column(name = "drowsy_seconds", nullable = false)
    private int drowsySeconds;

    @Column(name = "posture_down_seconds", nullable = false)
    private int postureDownSeconds;

    @Column(name = "away_seconds", nullable = false)
    private int awaySeconds;

    @Column(name = "paused_seconds", nullable = false)
    private int pausedSeconds;

    @Column(name = "break_seconds", nullable = false)
    private int breakSeconds;

    @Column(name = "reminder_count", nullable = false)
    private int reminderCount;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "summary", columnDefinition = "jsonb", nullable = false)
    private Map<String, Object> summary = new HashMap<>();

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "config", columnDefinition = "jsonb", nullable = false)
    private Map<String, Object> config = new HashMap<>();

    @Column(name = "revision", nullable = false)
    private int revision;

    @Column(name = "schema_version", nullable = false)
    private int schemaVersion = 1;

    @Column(name = "created_at", nullable = false, updatable = false)
    private OffsetDateTime createdAt;

    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt;

    @PrePersist
    public void prePersist() {
        OffsetDateTime now = OffsetDateTime.now();
        if (id == null) {
            id = UUID.randomUUID();
        }
        if (startAt == null) {
            startAt = now;
        }
        if (status == null || status.isBlank()) {
            status = "active";
        }
        if (timezone == null || timezone.isBlank()) {
            timezone = "Asia/Taipei";
        }
        if (summary == null) {
            summary = new HashMap<>();
        }
        if (config == null) {
            config = new HashMap<>();
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

    public UUID getId() {
        return id;
    }

    public void setId(UUID id) {
        this.id = id;
    }

    public User getUser() {
        return user;
    }

    public void setUser(User user) {
        this.user = user;
    }

    public UUID getClientSessionId() {
        return clientSessionId;
    }

    public void setClientSessionId(UUID clientSessionId) {
        this.clientSessionId = clientSessionId;
    }

    public OffsetDateTime getStartAt() {
        return startAt;
    }

    public void setStartAt(OffsetDateTime startAt) {
        this.startAt = startAt;
    }

    public OffsetDateTime getEndAt() {
        return endAt;
    }

    public void setEndAt(OffsetDateTime endAt) {
        this.endAt = endAt;
    }

    public String getStatus() {
        return status;
    }

    public void setStatus(String status) {
        this.status = status;
    }

    public String getEndReason() {
        return endReason;
    }

    public void setEndReason(String endReason) {
        this.endReason = endReason;
    }

    public String getMode() {
        return mode;
    }

    public void setMode(String mode) {
        this.mode = mode;
    }

    public String getTimezone() {
        return timezone;
    }

    public void setTimezone(String timezone) {
        this.timezone = timezone;
    }

    public Integer getTargetSeconds() {
        return targetSeconds;
    }

    public void setTargetSeconds(Integer targetSeconds) {
        this.targetSeconds = targetSeconds;
    }

    public int getMonitoredSeconds() {
        return monitoredSeconds;
    }

    public void setMonitoredSeconds(int monitoredSeconds) {
        this.monitoredSeconds = monitoredSeconds;
    }

    public int getFocusSeconds() {
        return focusSeconds;
    }

    public void setFocusSeconds(int focusSeconds) {
        this.focusSeconds = focusSeconds;
    }

    public int getDistractedSeconds() {
        return distractedSeconds;
    }

    public void setDistractedSeconds(int distractedSeconds) {
        this.distractedSeconds = distractedSeconds;
    }

    public int getAttentionSeconds() {
        return attentionSeconds;
    }

    public void setAttentionSeconds(int attentionSeconds) {
        this.attentionSeconds = attentionSeconds;
    }

    public int getFatigueSeconds() {
        return fatigueSeconds;
    }

    public void setFatigueSeconds(int fatigueSeconds) {
        this.fatigueSeconds = fatigueSeconds;
    }

    public int getDrowsySeconds() {
        return drowsySeconds;
    }

    public void setDrowsySeconds(int drowsySeconds) {
        this.drowsySeconds = drowsySeconds;
    }

    public int getPostureDownSeconds() {
        return postureDownSeconds;
    }

    public void setPostureDownSeconds(int postureDownSeconds) {
        this.postureDownSeconds = postureDownSeconds;
    }

    public int getAwaySeconds() {
        return awaySeconds;
    }

    public void setAwaySeconds(int awaySeconds) {
        this.awaySeconds = awaySeconds;
    }

    public int getPausedSeconds() {
        return pausedSeconds;
    }

    public void setPausedSeconds(int pausedSeconds) {
        this.pausedSeconds = pausedSeconds;
    }

    public int getBreakSeconds() {
        return breakSeconds;
    }

    public void setBreakSeconds(int breakSeconds) {
        this.breakSeconds = breakSeconds;
    }

    public int getReminderCount() {
        return reminderCount;
    }

    public void setReminderCount(int reminderCount) {
        this.reminderCount = reminderCount;
    }

    public Map<String, Object> getSummary() {
        return summary;
    }

    public void setSummary(Map<String, Object> summary) {
        this.summary = summary;
    }

    public Map<String, Object> getConfig() {
        return config;
    }

    public void setConfig(Map<String, Object> config) {
        this.config = config;
    }

    public int getRevision() {
        return revision;
    }

    public void setRevision(int revision) {
        this.revision = revision;
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
