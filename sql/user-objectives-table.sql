-- User Objectives Table (Normalized Schema)
-- Allows unlimited objective types without schema changes

-- 1. Create the user_objectives table
CREATE TABLE IF NOT EXISTS user_objectives (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    objective_type TEXT NOT NULL,
    target_value NUMERIC(10,2) NOT NULL,
    enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, objective_type)
);

-- 2. Add constraint for known objective types (can be expanded later)
ALTER TABLE user_objectives DROP CONSTRAINT IF EXISTS user_objectives_type_check;
ALTER TABLE user_objectives ADD CONSTRAINT user_objectives_type_check 
    CHECK (objective_type IN ('pushups', 'run', 'screentime', 'meditation', 'steps', 'water', 'sleep'));

-- 3. Indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_user_objectives_user ON user_objectives(user_id);
CREATE INDEX IF NOT EXISTS idx_user_objectives_enabled ON user_objectives(user_id, enabled) WHERE enabled = true;

-- 4. Migrate existing data from users table (if any)
-- Migrate pushups objectives
INSERT INTO user_objectives (user_id, objective_type, target_value, enabled)
SELECT id, 'pushups', COALESCE(objective_count, 50), true
FROM users 
WHERE objective_count IS NOT NULL AND objective_count > 0
ON CONFLICT (user_id, objective_type) DO NOTHING;

-- 5. Add objective_type to objective_sessions if not exists (for multi-objective tracking)
ALTER TABLE objective_sessions ADD COLUMN IF NOT EXISTS objective_type TEXT DEFAULT 'pushups';

-- 6. Update function to auto-update updated_at
CREATE OR REPLACE FUNCTION update_user_objectives_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS user_objectives_updated_at ON user_objectives;
CREATE TRIGGER user_objectives_updated_at
    BEFORE UPDATE ON user_objectives
    FOR EACH ROW
    EXECUTE FUNCTION update_user_objectives_timestamp();
