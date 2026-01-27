-- Add objective-related columns to users table
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS objective_type VARCHAR(50) DEFAULT 'pushups',
ADD COLUMN IF NOT EXISTS objective_count INTEGER DEFAULT 50,
ADD COLUMN IF NOT EXISTS objective_schedule VARCHAR(20) DEFAULT 'daily', -- 'daily' or 'weekdays'
ADD COLUMN IF NOT EXISTS objective_deadline TIME DEFAULT '09:00:00',
ADD COLUMN IF NOT EXISTS missed_goal_payout DECIMAL(10,2) DEFAULT 0.00,
ADD COLUMN IF NOT EXISTS payout_destination VARCHAR(20) DEFAULT 'charity', -- 'charity' or 'custom'
ADD COLUMN IF NOT EXISTS custom_recipient_id UUID REFERENCES recipients(id),
ADD COLUMN IF NOT EXISTS timezone VARCHAR(50) DEFAULT 'America/New_York';

-- Create table for tracking daily objective sessions
CREATE TABLE IF NOT EXISTS objective_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_date DATE NOT NULL,
    objective_type VARCHAR(50) NOT NULL,
    objective_count INTEGER NOT NULL,
    completed_count INTEGER DEFAULT 0,
    status VARCHAR(20) DEFAULT 'pending', -- 'pending', 'in_progress', 'completed', 'missed', 'skipped'
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    deadline_time TIME NOT NULL,
    payout_triggered BOOLEAN DEFAULT FALSE,
    payout_amount DECIMAL(10,2),
    payout_transaction_id UUID REFERENCES transactions(id),
    video_proof_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, session_date)
);

-- Create table for objective completion logs (individual reps/sets)
CREATE TABLE IF NOT EXISTS objective_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES objective_sessions(id) ON DELETE CASCADE,
    rep_count INTEGER NOT NULL,
    logged_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    video_url TEXT,
    metadata JSONB
);

-- Create index for faster queries
CREATE INDEX IF NOT EXISTS idx_objective_sessions_user_date ON objective_sessions(user_id, session_date);
CREATE INDEX IF NOT EXISTS idx_objective_sessions_status ON objective_sessions(status);
CREATE INDEX IF NOT EXISTS idx_objective_sessions_payout ON objective_sessions(payout_triggered);

-- Create a view for today's objectives
CREATE OR REPLACE VIEW today_objectives AS
SELECT 
    u.id as user_id,
    u.email,
    u.full_name,
    u.objective_type,
    u.objective_count,
    u.objective_deadline,
    u.missed_goal_payout,
    u.payout_destination,
    os.id as session_id,
    os.status,
    os.completed_count,
    os.started_at,
    os.payout_triggered,
    CASE 
        WHEN os.status = 'completed' THEN 'Success ✅'
        WHEN os.status = 'missed' AND os.payout_triggered THEN 'Missed - Payout Sent 💸'
        WHEN os.status = 'missed' THEN 'Missed - Pending Payout ⏳'
        WHEN CURRENT_TIME > u.objective_deadline THEN 'Overdue ⚠️'
        ELSE 'In Progress 🏃'
    END as status_display
FROM users u
LEFT JOIN objective_sessions os ON u.id = os.user_id 
    AND os.session_date = CURRENT_DATE
WHERE u.objective_count > 0;

-- Function to check and create daily objective sessions
CREATE OR REPLACE FUNCTION create_daily_objective_sessions()
RETURNS void AS $$
BEGIN
    INSERT INTO objective_sessions (
        user_id, 
        session_date, 
        objective_type, 
        objective_count, 
        deadline_time,
        status
    )
    SELECT 
        u.id,
        CURRENT_DATE,
        u.objective_type,
        u.objective_count,
        u.objective_deadline,
        'pending'
    FROM users u
    WHERE u.objective_count > 0
        AND (
            (u.objective_schedule = 'daily') 
            OR 
            (u.objective_schedule = 'weekdays' AND EXTRACT(DOW FROM CURRENT_DATE) BETWEEN 1 AND 5)
        )
        AND NOT EXISTS (
            SELECT 1 FROM objective_sessions os 
            WHERE os.user_id = u.id 
            AND os.session_date = CURRENT_DATE
        );
END;
$$ LANGUAGE plpgsql;

-- Function to check for missed objectives and trigger payouts
CREATE OR REPLACE FUNCTION check_missed_objectives()
RETURNS TABLE(
    session_id UUID,
    user_id UUID,
    user_email VARCHAR,
    payout_amount DECIMAL,
    payout_destination VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    UPDATE objective_sessions os
    SET 
        status = 'missed',
        updated_at = NOW()
    FROM users u
    WHERE os.user_id = u.id
        AND os.session_date = CURRENT_DATE
        AND os.status IN ('pending', 'in_progress')
        AND CURRENT_TIME > os.deadline_time
        AND os.completed_count < os.objective_count
        AND NOT os.payout_triggered
    RETURNING 
        os.id,
        os.user_id,
        u.email,
        u.missed_goal_payout,
        u.payout_destination;
END;
$$ LANGUAGE plpgsql;

-- Row Level Security
ALTER TABLE objective_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE objective_logs ENABLE ROW LEVEL SECURITY;

-- Policies for objective_sessions
CREATE POLICY "Users can view their own objective sessions"
    ON objective_sessions FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can update their own objective sessions"
    ON objective_sessions FOR UPDATE
    USING (auth.uid() = user_id);

CREATE POLICY "Service role can manage all objective sessions"
    ON objective_sessions FOR ALL
    USING (auth.role() = 'service_role');

-- Policies for objective_logs
CREATE POLICY "Users can view their own objective logs"
    ON objective_logs FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM objective_sessions os 
        WHERE os.id = objective_logs.session_id 
        AND os.user_id = auth.uid()
    ));

CREATE POLICY "Users can insert their own objective logs"
    ON objective_logs FOR INSERT
    WITH CHECK (EXISTS (
        SELECT 1 FROM objective_sessions os 
        WHERE os.id = objective_logs.session_id 
        AND os.user_id = auth.uid()
    ));

CREATE POLICY "Service role can manage all objective logs"
    ON objective_logs FOR ALL
    USING (auth.role() = 'service_role');