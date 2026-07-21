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

import java.time.OffsetDateTime;
import java.util.UUID;

@Entity
@Table(name = "focus_rounds")
public class FocusRound {

    @Id
    @Column(name = "id", nullable = false, updatable = false)
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id", nullable = false)
    private User user;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "session_id", nullable = false)
    private FocusSession session;

    @Column(name = "client_round_id")
    private UUID clientRoundId;

    @Column(name = "round_number", nullable = false)
    private int roundNumber;

    @Column(name = "round_type", nullable = false)
    private String roundType;

    @Column(name = "status", nullable = false)
    private String status;

    @Column(name = "target_seconds", nullable = false)
    private int targetSeconds;

    @Column(name = "actual_seconds", nullable = false)
    private int actualSeconds;

    @Column(name = "paused_seconds", nullable = false)
    private int pausedSeconds;

    @Column(name = "start_at", nullable = false)
    private OffsetDateTime startAt;

    @Column(name = "end_at")
    private OffsetDateTime endAt;

    @Column(name = "end_reason")
    private String endReason;

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
        if (roundType == null || roundType.isBlank()) {
            roundType = "focus";
        }
        if (status == null || status.isBlank()) {
            status = "active";
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

    public FocusSession getSession() {
        return session;
    }

    public void setSession(FocusSession session) {
        this.session = session;
    }

    public UUID getClientRoundId() {
        return clientRoundId;
    }

    public void setClientRoundId(UUID clientRoundId) {
        this.clientRoundId = clientRoundId;
    }

    public int getRoundNumber() {
        return roundNumber;
    }

    public void setRoundNumber(int roundNumber) {
        this.roundNumber = roundNumber;
    }

    public String getRoundType() {
        return roundType;
    }

    public void setRoundType(String roundType) {
        this.roundType = roundType;
    }

    public String getStatus() {
        return status;
    }

    public void setStatus(String status) {
        this.status = status;
    }

    public int getTargetSeconds() {
        return targetSeconds;
    }

    public void setTargetSeconds(int targetSeconds) {
        this.targetSeconds = targetSeconds;
    }

    public int getActualSeconds() {
        return actualSeconds;
    }

    public void setActualSeconds(int actualSeconds) {
        this.actualSeconds = actualSeconds;
    }

    public int getPausedSeconds() {
        return pausedSeconds;
    }

    public void setPausedSeconds(int pausedSeconds) {
        this.pausedSeconds = pausedSeconds;
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

    public String getEndReason() {
        return endReason;
    }

    public void setEndReason(String endReason) {
        this.endReason = endReason;
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
