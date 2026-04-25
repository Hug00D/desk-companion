-- 0. 確保加密擴充功能存在 (為了 gen_random_uuid)
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1. 建立 users 資料表
CREATE TABLE users (
    -- 基本主鍵與帳密 (使用 UUID 與 TEXT)
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE,
    password_hash TEXT,
    
    -- 第三方登入相關
    google_id TEXT UNIQUE,
    auth_provider TEXT NOT NULL DEFAULT 'EMAIL',
    
    -- 狀態與驗證 (預設大寫)
    email_verified BOOLEAN NOT NULL DEFAULT false,
    email_verified_at TIMESTAMPTZ,
    account_status TEXT NOT NULL DEFAULT 'ACTIVE',
    
    -- 時間戳記 (使用帶時區的 TIMESTAMPTZ)
    last_login_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- 邏輯約束 (Constraints) - 全部改為大寫規範
    CONSTRAINT users_email_or_google_check 
        CHECK (email IS NOT NULL OR google_id IS NOT NULL),
    CONSTRAINT users_auth_provider_check 
        CHECK (auth_provider IN ('EMAIL', 'GOOGLE', 'BOTH')),
    CONSTRAINT users_account_status_check 
        CHECK (account_status IN ('ACTIVE', 'SUSPENDED', 'DELETED'))
);

-- 2. 建立自動更新 updated_at 的 Function
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. 綁定觸發器到 users 表
CREATE TRIGGER trg_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

-- 1) password_reset_tokens
CREATE TABLE password_reset_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(64) NOT NULL UNIQUE, -- 增加 UNIQUE 約束
    expires_at TIMESTAMPTZ NOT NULL,
    used_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2) profiles
CREATE TABLE profiles (
    id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    display_name TEXT,
    avatar_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

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

-- password_reset_tokens
CREATE INDEX idx_password_reset_tokens_user_id ON password_reset_tokens(user_id);

-- focus_sessions
CREATE INDEX idx_focus_sessions_user_id_start_at ON focus_sessions(user_id, start_at DESC);
CREATE INDEX idx_focus_sessions_start_at ON focus_sessions(start_at);

-- behavior_events
CREATE INDEX idx_behavior_events_user_id_ts ON behavior_events(user_id, ts DESC);
CREATE INDEX idx_behavior_events_session_id_ts ON behavior_events(session_id, ts ASC);
CREATE INDEX idx_behavior_events_event_type_ts ON behavior_events(event_type, ts DESC);

-- chat_history
CREATE INDEX idx_chat_history_user_id_created_at ON chat_history(user_id, created_at DESC);
CREATE INDEX idx_chat_history_session_id_created_at ON chat_history(session_id, created_at ASC);

-- user_memories
CREATE INDEX idx_user_memories_user_id_updated_at ON user_memories(user_id, updated_at DESC);
CREATE INDEX idx_user_memories_user_id_scope ON user_memories(user_id, memory_scope);

-- 建立共用的更新函數
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE 'plpgsql';

-- 自動為所有包含 updated_at 欄位的表建立 Trigger
DO $$
DECLARE
    t text;
BEGIN
    FOR t IN
        SELECT table_name
        FROM information_schema.columns
        WHERE column_name = 'updated_at'
          AND table_schema = 'public'
          AND table_name NOT LIKE 'pg_%' -- 排除系統表
    LOOP
        EXECUTE format(
            'CREATE TRIGGER %I BEFORE UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();',
            t || '_set_updated_at',
            t
        );
    END LOOP;
END $$;