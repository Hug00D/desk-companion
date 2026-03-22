-- 3) character_stats
CREATE TABLE character_stats (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    character_type TEXT,
    favorability INT NOT NULL DEFAULT 0 CHECK (favorability >= 0),
    current_outfit_id TEXT,
    last_interaction TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 4) focus_sessions
CREATE TABLE focus_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    start_at TIMESTAMPTZ NOT NULL,
    end_at TIMESTAMPTZ,
    mode TEXT,
    target_seconds INT CHECK (target_seconds IS NULL OR target_seconds > 0),
    focus_seconds INT NOT NULL DEFAULT 0 CHECK (focus_seconds >= 0),
    distracted_seconds INT NOT NULL DEFAULT 0 CHECK (distracted_seconds >= 0),
    away_seconds INT NOT NULL DEFAULT 0 CHECK (away_seconds >= 0),
    reminder_count INT NOT NULL DEFAULT 0 CHECK (reminder_count >= 0),
    summary JSONB NOT NULL DEFAULT '{}'::jsonb,
    config JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT focus_sessions_time_check
        CHECK (end_at IS NULL OR end_at >= start_at)
);

-- 5) behavior_events
CREATE TABLE behavior_events (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_id UUID REFERENCES focus_sessions(id) ON DELETE SET NULL,
    ts TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    event_type TEXT NOT NULL,
    detected_object TEXT,
    confidence_score DOUBLE PRECISION,
    signals JSONB NOT NULL DEFAULT '{}'::jsonb,
    action_triggered TEXT,
    debug_snapshot_path TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 6) chat_history
CREATE TABLE chat_history (
    id BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_id UUID REFERENCES focus_sessions(id) ON DELETE SET NULL,
    sender TEXT NOT NULL,
    message_content TEXT NOT NULL,
    interaction_type TEXT,
    -- 修正為 behavior_event_id 以保持一致性
    behavior_event_id BIGINT REFERENCES behavior_events(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT chat_history_sender_check
        CHECK (sender IN ('user', 'assistant', 'system'))
);

-- 7) user_memories
CREATE TABLE user_memories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    memory_scope TEXT NOT NULL,
    level SMALLINT NOT NULL,
    kind TEXT NOT NULL,
    title TEXT,
    content TEXT NOT NULL,
    tags TEXT[],
    importance SMALLINT NOT NULL DEFAULT 3,
    source TEXT,
    evidence JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT user_memories_scope_check
        CHECK (memory_scope IN ('short_term', 'long_term')),
    CONSTRAINT user_memories_level_check
        CHECK (level IN (1, 2)),
    CONSTRAINT user_memories_importance_check
        CHECK (importance BETWEEN 1 AND 5),
    CONSTRAINT user_memories_source_check
        CHECK (source IN ('user_input', 'inferred', 'system'))
);