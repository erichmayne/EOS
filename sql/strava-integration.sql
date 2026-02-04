-- Strava Integration Schema
-- Run this AFTER the existing tables are created

-- 1. Create strava_connections table (if not exists)
CREATE TABLE IF NOT EXISTS strava_connections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    strava_user_id BIGINT UNIQUE NOT NULL,
    access_token TEXT NOT NULL,
    refresh_token TEXT NOT NULL,
    token_expires_at TIMESTAMPTZ NOT NULL,
    athlete_name TEXT,
    connected_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Add strava_connection_id to users (if not exists)
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'users' AND column_name = 'strava_connection_id'
    ) THEN
        ALTER TABLE users ADD COLUMN strava_connection_id UUID REFERENCES strava_connections(id);
    END IF;
END $$;

-- 3. Ensure objective_type column exists
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'users' AND column_name = 'objective_type'
    ) THEN
        ALTER TABLE users ADD COLUMN objective_type TEXT DEFAULT 'pushups';
    END IF;
END $$;

-- 4. Update constraint to include 'run' (safe - drops if exists first)
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_objective_type_check;
ALTER TABLE users ADD CONSTRAINT users_objective_type_check 
    CHECK (objective_type IN ('pushups', 'run'));

-- Index for webhook lookups
CREATE INDEX IF NOT EXISTS idx_strava_connections_user_id ON strava_connections(strava_user_id);
