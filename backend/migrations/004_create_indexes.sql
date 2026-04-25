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