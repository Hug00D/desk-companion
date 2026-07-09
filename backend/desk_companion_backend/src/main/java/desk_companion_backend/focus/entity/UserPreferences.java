package desk_companion_backend.focus.entity;

import desk_companion_backend.user.entity.User;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.MapsId;
import jakarta.persistence.OneToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;

import java.time.OffsetDateTime;
import java.util.UUID;

@Entity
@Table(name = "user_preferences")
public class UserPreferences {

    @Id
    @Column(name = "user_id", nullable = false)
    private UUID userId;

    @OneToOne(fetch = FetchType.LAZY)
    @MapsId
    @JoinColumn(name = "user_id")
    private User user;

    @Column(name = "quiet_mode", nullable = false)
    private boolean quietMode;

    @Column(name = "reminder_sensitivity", nullable = false)
    private String reminderSensitivity = "normal";

    @Column(name = "ai_response_tone", nullable = false)
    private String aiResponseTone = "supportive";

    @Column(name = "timezone", nullable = false)
    private String timezone = "Asia/Taipei";

    @Column(name = "sync_enabled", nullable = false)
    private boolean syncEnabled = true;

    @Column(name = "store_transcript", nullable = false)
    private boolean storeTranscript;

    @Column(name = "store_debug_snapshot", nullable = false)
    private boolean storeDebugSnapshot;

    @Column(name = "schema_version", nullable = false)
    private int schemaVersion = 1;

    @Column(name = "created_at", nullable = false, updatable = false)
    private OffsetDateTime createdAt;

    @Column(name = "updated_at", nullable = false)
    private OffsetDateTime updatedAt;

    @PrePersist
    public void prePersist() {
        OffsetDateTime now = OffsetDateTime.now();
        if (reminderSensitivity == null || reminderSensitivity.isBlank()) {
            reminderSensitivity = "normal";
        }
        if (aiResponseTone == null || aiResponseTone.isBlank()) {
            aiResponseTone = "supportive";
        }
        if (timezone == null || timezone.isBlank()) {
            timezone = "Asia/Taipei";
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

    public UUID getUserId() {
        return userId;
    }

    public User getUser() {
        return user;
    }

    public void setUser(User user) {
        this.user = user;
    }

    public boolean isQuietMode() {
        return quietMode;
    }

    public void setQuietMode(boolean quietMode) {
        this.quietMode = quietMode;
    }

    public String getReminderSensitivity() {
        return reminderSensitivity;
    }

    public void setReminderSensitivity(String reminderSensitivity) {
        this.reminderSensitivity = reminderSensitivity;
    }

    public String getAiResponseTone() {
        return aiResponseTone;
    }

    public void setAiResponseTone(String aiResponseTone) {
        this.aiResponseTone = aiResponseTone;
    }

    public String getTimezone() {
        return timezone;
    }

    public void setTimezone(String timezone) {
        this.timezone = timezone;
    }

    public boolean isSyncEnabled() {
        return syncEnabled;
    }

    public void setSyncEnabled(boolean syncEnabled) {
        this.syncEnabled = syncEnabled;
    }

    public boolean isStoreTranscript() {
        return storeTranscript;
    }

    public void setStoreTranscript(boolean storeTranscript) {
        this.storeTranscript = storeTranscript;
    }

    public boolean isStoreDebugSnapshot() {
        return storeDebugSnapshot;
    }

    public void setStoreDebugSnapshot(boolean storeDebugSnapshot) {
        this.storeDebugSnapshot = storeDebugSnapshot;
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
