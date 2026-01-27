-- Multi-Objective System Schema Extension
-- This ADDS to existing schema without breaking current functionality

-- Create user objectives table for future multi-objective support
CREATE TABLE IF NOT EXISTS user_objectives (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    objective_type VARCHAR(50) NOT NULL,
    target_value DECIMAL(10,2) NOT NULL,
    target_unit VARCHAR(20) NOT NULL, -- 'reps', 'minutes', 'miles', etc.
    direction VARCHAR(20) DEFAULT 'meet_or_exceed', -- 'meet_or_exceed', 'stay_under'
    deadline TIME NOT NULL,
    schedule VARCHAR(20) DEFAULT 'daily',
    active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create extended sessions table for future use
CREATE TABLE IF NOT EXISTS objective_sessions_v2 (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_date DATE NOT NULL,
    objectives JSONB NOT NULL, -- Stores all objectives and their status
    overall_status VARCHAR(20) DEFAULT 'pending',
    payout_amount DECIMAL(10,2),
    payout_triggered BOOLEAN DEFAULT FALSE,
    payout_transaction_id UUID REFERENCES transactions(id),
    earliest_deadline TIME,
    latest_deadline TIME,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, session_date)
);

-- Add indexes
CREATE INDEX IF NOT EXISTS idx_user_objectives_user_id ON user_objectives(user_id);
CREATE INDEX IF NOT EXISTS idx_user_objectives_active ON user_objectives(active);
CREATE INDEX IF NOT EXISTS idx_objective_sessions_v2_user_date ON objective_sessions_v2(user_id, session_date);
CREATE INDEX IF NOT EXISTS idx_objective_sessions_v2_status ON objective_sessions_v2(overall_status);

-- Enable RLS
ALTER TABLE user_objectives ENABLE ROW LEVEL SECURITY;
ALTER TABLE objective_sessions_v2 ENABLE ROW LEVEL SECURITY;

-- Policies for user_objectives
DROP POLICY IF EXISTS "Users can view their own objectives" ON user_objectives;
CREATE POLICY "Users can view their own objectives"
    ON user_objectives FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can manage their own objectives" ON user_objectives;
CREATE POLICY "Users can manage their own objectives"
    ON user_objectives FOR ALL
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Service role can manage all objectives" ON user_objectives;
CREATE POLICY "Service role can manage all objectives"
    ON user_objectives FOR ALL
    USING (auth.role() = 'service_role');

-- Policies for objective_sessions_v2
DROP POLICY IF EXISTS "Users can view their own sessions v2" ON objective_sessions_v2;
CREATE POLICY "Users can view their own sessions v2"
    ON objective_sessions_v2 FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Service role can manage all sessions v2" ON objective_sessions_v2;
CREATE POLICY "Service role can manage all sessions v2"
    ON objective_sessions_v2 FOR ALL
    USING (auth.role() = 'service_role');

-- Migration helper function (for future use)
CREATE OR REPLACE FUNCTION migrate_to_multi_objectives()
RETURNS void
LANGUAGE plpgsql
AS $function$
BEGIN
    -- This function will migrate single objectives to multi when ready
    -- Currently does nothing to preserve existing functionality
    RAISE NOTICE 'Multi-objective tables ready for future migration';
END;
$function$;