ALTER TABLE password_reset_tokens RENAME TO verification_tokens;

ALTER INDEX idx_password_reset_tokens_user_id RENAME TO idx_verification_tokens_user_id;

ALTER TABLE verification_tokens ADD COLUMN token_type VARCHAR(32);

UPDATE verification_tokens
SET token_type = 'PASSWORD_RESET'
WHERE token_type IS NULL;

ALTER TABLE verification_tokens ALTER COLUMN token_type SET NOT NULL;

ALTER TABLE verification_tokens
ADD CONSTRAINT verification_tokens_token_type_check
CHECK (token_type IN (
    'PASSWORD_RESET',
    'EMAIL_VERIFICATION',
    'ACCOUNT_RECOVERY'
));

CREATE INDEX idx_verification_tokens_user_id_type_created_at
    ON verification_tokens(user_id, token_type, created_at DESC);
