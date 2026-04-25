-- 0) users
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE,
    password_hash TEXT,
    google_id TEXT UNIQUE,
    auth_provider TEXT NOT NULL DEFAULT 'EMAIL'
    email_verified BOOLEAN NOT NULL DEFAULT false,
    email_verified_at TIMESTAMPTZ,
    account_status TEXT NOT NULL DEFAULT 'ACTIVE'
    last_login_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT users_email_or_google_check
        CHECK (email IS NOT NULL OR google_id IS NOT NULL),
    CONSTRAINT users_auth_provider_check
        CHECK (auth_provider IN ('EMAIL', 'GOOGLE', 'BOTH'))
    CONSTRAINT users_account_status_check
        CHECK (account_status IN ('ACTIVE', 'SUSPENDED', 'DELETED'))
);

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