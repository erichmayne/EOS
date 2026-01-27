-- Simplified Objective Tracking Schema for EOS
-- Run this in your Supabase SQL Editor

-- Create transactions table first (if it doesn't exist)
CREATE TABLE IF NOT EXISTS transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type VARCHAR(50) NOT NULL, -- 'deposit', 'payout', 'refund'
    amount_cents INTEGER NOT NULL,
    status VARCHAR(50) DEFAULT 'pending', -- 'pending', 'completed', 'failed', 'cancelled'
    description TEXT,
    stripe_payment_id VARCHAR(255),
    stripe_payment_method_id VARCHAR(255),
    processed_at TIMESTAMP WITH TIME ZONE,
    metadata JSONB,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for transactions
CREATE INDEX IF NOT EXISTS idx_transactions_user_id ON transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_transactions_status ON transactions(status);
CREATE INDEX IF NOT EXISTS idx_transactions_type ON transactions(type);

-- Add objective-related columns to users table
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS objective_type VARCHAR(50) DEFAULT 'pushups',
ADD COLUMN IF NOT EXISTS objective_count INTEGER DEFAULT 50,
ADD COLUMN IF NOT EXISTS objective_schedule VARCHAR(20) DEFAULT 'daily', -- 'daily' or 'weekdays'
ADD COLUMN IF NOT EXISTS objective_deadline TIME DEFAULT '09:00:00',
ADD COLUMN IF NOT EXISTS missed_goal_payout DECIMAL(10,2) DEFAULT 0.00,
ADD COLUMN IF NOT EXISTS payout_destination VARCHAR(20) DEFAULT 'charity', -- 'charity' or 'custom'
ADD COLUMN IF NOT EXISTS custom_recipient_id UUID REFERENCES recipients(id),
ADD COLUMN IF NOT EXISTS payout_committed BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS timezone VARCHAR(50) DEFAULT 'America/New_York';

-- Create table for tracking daily objective sessions
CREATE TABLE IF NOT EXISTS objective_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    session_date DATE NOT NULL,
    objective_type VARCHAR(50) NOT NULL,
    objective_count INTEGER NOT NULL,
    completed_count INTEGER DEFAULT 0,
    status VARCHAR(20) DEFAULT 'pending', -- 'pending', 'in_progress', 'completed', 'missed'
    started_at TIMESTAMP WITH TIME ZONE,
    completed_at TIMESTAMP WITH TIME ZONE,
    deadline_time TIME NOT NULL,
    payout_triggered BOOLEAN DEFAULT FALSE,
    payout_amount DECIMAL(10,2),
    payout_transaction_id UUID REFERENCES transactions(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, session_date)
);

-- Create indexes for faster queries
CREATE INDEX IF NOT EXISTS idx_objective_sessions_user_date ON objective_sessions(user_id, session_date);
CREATE INDEX IF NOT EXISTS idx_objective_sessions_status ON objective_sessions(status);
CREATE INDEX IF NOT EXISTS idx_objective_sessions_payout ON objective_sessions(payout_triggered);

-- Function to check and create daily objective sessions
CREATE OR REPLACE FUNCTION create_daily_objective_sessions()
RETURNS void 
LANGUAGE plpgsql
AS $function$
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
        AND u.payout_committed = true  -- Only create sessions for users with committed payouts
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
$function$;

-- Function to check for missed objectives and trigger payouts
CREATE OR REPLACE FUNCTION check_missed_objectives()
RETURNS TABLE(
    session_id UUID,
    user_id UUID,
    user_email VARCHAR,
    payout_amount DECIMAL,
    payout_destination VARCHAR
) 
LANGUAGE plpgsql
AS $function$
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
$function$;

-- Row Level Security
ALTER TABLE objective_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;

-- Policies for transactions (drop existing and recreate)
DROP POLICY IF EXISTS "Users can view their own transactions" ON transactions;
CREATE POLICY "Users can view their own transactions"
    ON transactions FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Service role can manage all transactions" ON transactions;
CREATE POLICY "Service role can manage all transactions"
    ON transactions FOR ALL
    USING (auth.role() = 'service_role');

-- Policies for objective_sessions (drop existing and recreate)
DROP POLICY IF EXISTS "Users can view their own objective sessions" ON objective_sessions;
CREATE POLICY "Users can view their own objective sessions"
    ON objective_sessions FOR SELECT
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update their own objective sessions" ON objective_sessions;
CREATE POLICY "Users can update their own objective sessions"
    ON objective_sessions FOR UPDATE
    USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Service role can manage all objective sessions" ON objective_sessions;
CREATE POLICY "Service role can manage all objective sessions"
    ON objective_sessions FOR ALL
    USING (auth.role() = 'service_role');