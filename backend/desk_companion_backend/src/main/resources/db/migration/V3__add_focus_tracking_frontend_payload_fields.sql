ALTER TABLE focus_sessions
    ADD COLUMN client_session_id UUID,
    ADD COLUMN status TEXT NOT NULL DEFAULT 'active',
    ADD COLUMN timezone TEXT NOT NULL DEFAULT 'Asia/Taipei',
    ADD COLUMN monitored_seconds INT NOT NULL DEFAULT 0 CHECK (monitored_seconds >= 0),
    ADD COLUMN attention_seconds INT NOT NULL DEFAULT 0 CHECK (attention_seconds >= 0),
    ADD COLUMN fatigue_seconds INT NOT NULL DEFAULT 0 CHECK (fatigue_seconds >= 0),
    ADD COLUMN drowsy_seconds INT NOT NULL DEFAULT 0 CHECK (drowsy_seconds >= 0),
    ADD COLUMN posture_down_seconds INT NOT NULL DEFAULT 0 CHECK (posture_down_seconds >= 0),
    ADD COLUMN paused_seconds INT NOT NULL DEFAULT 0 CHECK (paused_seconds >= 0),
    ADD COLUMN break_seconds INT NOT NULL DEFAULT 0 CHECK (break_seconds >= 0),
    ADD COLUMN end_reason TEXT,
    ADD COLUMN revision INT NOT NULL DEFAULT 0 CHECK (revision >= 0),
    ADD COLUMN schema_version INT NOT NULL DEFAULT 1 CHECK (schema_version > 0);

ALTER TABLE focus_sessions
    ADD CONSTRAINT focus_sessions_status_check
        CHECK (status IN ('active', 'completed', 'stopped', 'abandoned')),
    ADD CONSTRAINT focus_sessions_end_reason_check
        CHECK (
            end_reason IS NULL OR
            end_reason IN ('completed', 'userStopped', 'appClosed', 'error', 'unknown')
        );

CREATE UNIQUE INDEX idx_focus_sessions_user_id_client_session_id
    ON focus_sessions(user_id, client_session_id)
    WHERE client_session_id IS NOT NULL;

CREATE INDEX idx_focus_sessions_user_id_status_start_at
    ON focus_sessions(user_id, status, start_at DESC);

CREATE TABLE focus_rounds (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_id UUID NOT NULL REFERENCES focus_sessions(id) ON DELETE CASCADE,
    client_round_id UUID,
    round_number INT NOT NULL CHECK (round_number > 0),
    round_type TEXT NOT NULL,
    status TEXT NOT NULL,
    target_seconds INT NOT NULL CHECK (target_seconds > 0),
    actual_seconds INT NOT NULL DEFAULT 0 CHECK (actual_seconds >= 0),
    paused_seconds INT NOT NULL DEFAULT 0 CHECK (paused_seconds >= 0),
    start_at TIMESTAMPTZ NOT NULL,
    end_at TIMESTAMPTZ,
    end_reason TEXT,
    schema_version INT NOT NULL DEFAULT 1 CHECK (schema_version > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT focus_rounds_round_type_check
        CHECK (round_type IN ('focus', 'break')),
    CONSTRAINT focus_rounds_status_check
        CHECK (status IN ('active', 'paused', 'completed', 'stopped')),
    CONSTRAINT focus_rounds_end_reason_check
        CHECK (
            end_reason IS NULL OR
            end_reason IN ('completed', 'userStopped', 'sessionEnded', 'error')
        ),
    CONSTRAINT focus_rounds_time_check
        CHECK (end_at IS NULL OR end_at >= start_at)
);

CREATE UNIQUE INDEX idx_focus_rounds_user_id_client_round_id
    ON focus_rounds(user_id, client_round_id)
    WHERE client_round_id IS NOT NULL;

CREATE INDEX idx_focus_rounds_session_id_round_number
    ON focus_rounds(session_id, round_number);

CREATE INDEX idx_focus_rounds_user_id_start_at
    ON focus_rounds(user_id, start_at DESC);

ALTER TABLE behavior_events
    ADD COLUMN client_event_id UUID,
    ADD COLUMN round_id UUID REFERENCES focus_rounds(id) ON DELETE SET NULL,
    ADD COLUMN related_event_id BIGINT REFERENCES behavior_events(id) ON DELETE SET NULL,
    ADD COLUMN source TEXT NOT NULL DEFAULT 'vision',
    ADD COLUMN severity TEXT NOT NULL DEFAULT 'info',
    ADD COLUMN phase TEXT NOT NULL DEFAULT 'point',
    ADD COLUMN duration_ms INT CHECK (duration_ms IS NULL OR duration_ms >= 0),
    ADD COLUMN outcome TEXT NOT NULL DEFAULT 'observed',
    ADD COLUMN schema_version INT NOT NULL DEFAULT 1 CHECK (schema_version > 0);

ALTER TABLE behavior_events
    ADD CONSTRAINT behavior_events_source_check
        CHECK (source IN ('vision', 'voice', 'timer', 'user', 'system')),
    ADD CONSTRAINT behavior_events_severity_check
        CHECK (severity IN ('info', 'attention', 'warning')),
    ADD CONSTRAINT behavior_events_phase_check
        CHECK (phase IN ('point', 'started', 'ended')),
    ADD CONSTRAINT behavior_events_outcome_check
        CHECK (
            outcome IN (
                'observed',
                'applied',
                'rejected',
                'shown',
                'accepted',
                'dismissed',
                'expired'
            )
        );

CREATE UNIQUE INDEX idx_behavior_events_user_id_client_event_id
    ON behavior_events(user_id, client_event_id)
    WHERE client_event_id IS NOT NULL;

CREATE INDEX idx_behavior_events_session_id_source_ts
    ON behavior_events(session_id, source, ts ASC);

CREATE INDEX idx_behavior_events_round_id_ts
    ON behavior_events(round_id, ts ASC);

CREATE TABLE user_preferences (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    quiet_mode BOOLEAN NOT NULL DEFAULT false,
    reminder_sensitivity TEXT NOT NULL DEFAULT 'normal',
    ai_response_tone TEXT NOT NULL DEFAULT 'supportive',
    timezone TEXT NOT NULL DEFAULT 'Asia/Taipei',
    sync_enabled BOOLEAN NOT NULL DEFAULT true,
    store_transcript BOOLEAN NOT NULL DEFAULT false,
    store_debug_snapshot BOOLEAN NOT NULL DEFAULT false,
    schema_version INT NOT NULL DEFAULT 1 CHECK (schema_version > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT user_preferences_reminder_sensitivity_check
        CHECK (reminder_sensitivity IN ('low', 'normal', 'high')),
    CONSTRAINT user_preferences_ai_response_tone_check
        CHECK (ai_response_tone IN ('supportive', 'encouraging', 'strict'))
);

CREATE TRIGGER trg_focus_rounds_updated_at
BEFORE UPDATE ON focus_rounds
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trg_user_preferences_updated_at
BEFORE UPDATE ON user_preferences
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();
