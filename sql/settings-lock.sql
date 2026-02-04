-- Settings Lock Feature
-- Add column to track when user settings are unlocked

ALTER TABLE users ADD COLUMN IF NOT EXISTS settings_locked_until TIMESTAMPTZ;

-- Index for quick lookups
CREATE INDEX IF NOT EXISTS idx_users_settings_locked ON users(settings_locked_until);

-- Comment for documentation
COMMENT ON COLUMN users.settings_locked_until IS 'Timestamp when objective settings can be changed again. Null or past date means unlocked.';
