-- EOS Payout System Fix
-- Run this in Supabase SQL Editor

-- 1. Add missing columns to users table
ALTER TABLE users ADD COLUMN IF NOT EXISTS destination_committed BOOLEAN DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS committed_destination VARCHAR(50);
ALTER TABLE users ADD COLUMN IF NOT EXISTS committed_recipient_id UUID;

-- 2. Drop and recreate objective_sessions table (clean slate)
DROP TABLE IF EXISTS objective_sessions CASCADE;
CREATE TABLE objective_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    session_date DATE NOT NULL DEFAULT CURRENT_DATE,
    objective_type VARCHAR(50) DEFAULT 'pushups',
    target_count INTEGER DEFAULT 50,
    completed_count INTEGER DEFAULT 0,
    deadline TIME,
    status VARCHAR(20) DEFAULT 'pending', -- pending, completed, missed
    payout_triggered BOOLEAN DEFAULT FALSE,
    payout_amount DECIMAL(10,2) DEFAULT 0,
    payout_transaction_id UUID,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, session_date)
);

-- 3. Drop and recreate the function to create daily sessions
DROP FUNCTION IF EXISTS create_daily_objective_sessions();
CREATE OR REPLACE FUNCTION create_daily_objective_sessions()
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    sessions_created INTEGER := 0;
BEGIN
    -- Create sessions for users who have committed payouts and don't have today's session
    INSERT INTO objective_sessions (user_id, session_date, objective_type, target_count, deadline)
    SELECT 
        u.id,
        CURRENT_DATE,
        COALESCE(u.objective_type, 'pushups'),
        COALESCE(u.objective_count, 50),
        COALESCE(u.objective_deadline, '09:00'::TIME)
    FROM users u
    WHERE u.payout_committed = true
    AND NOT EXISTS (
        SELECT 1 FROM objective_sessions os 
        WHERE os.user_id = u.id AND os.session_date = CURRENT_DATE
    );
    
    GET DIAGNOSTICS sessions_created = ROW_COUNT;
    RETURN sessions_created;
END;
$$;

-- 4. Drop and recreate the function to check missed objectives
DROP FUNCTION IF EXISTS check_missed_objectives();
CREATE OR REPLACE FUNCTION check_missed_objectives()
RETURNS TABLE (
    session_id UUID,
    user_id UUID,
    user_email VARCHAR,
    payout_amount DECIMAL,
    payout_destination VARCHAR,
    recipient_id UUID,
    recipient_stripe_id VARCHAR
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        os.id as session_id,
        os.user_id,
        u.email as user_email,
        u.missed_goal_payout as payout_amount,
        COALESCE(u.committed_destination, u.payout_destination) as payout_destination,
        COALESCE(u.committed_recipient_id, u.custom_recipient_id) as recipient_id,
        r.stripe_connect_account_id as recipient_stripe_id
    FROM objective_sessions os
    JOIN users u ON os.user_id = u.id
    LEFT JOIN recipients r ON r.id = COALESCE(u.committed_recipient_id, u.custom_recipient_id)
    WHERE os.session_date = CURRENT_DATE
    AND os.status = 'pending'
    AND os.payout_triggered = false
    AND os.deadline < CURRENT_TIME
    AND os.completed_count < os.target_count
    AND u.payout_committed = true
    AND u.missed_goal_payout > 0;
END;
$$;

-- 5. Drop and recreate function to process a payout (deduct balance, mark session)
DROP FUNCTION IF EXISTS process_payout(UUID, UUID);
CREATE OR REPLACE FUNCTION process_payout(
    p_session_id UUID,
    p_transaction_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    v_user_id UUID;
    v_payout_amount DECIMAL;
BEGIN
    -- Get session info
    SELECT os.user_id, u.missed_goal_payout
    INTO v_user_id, v_payout_amount
    FROM objective_sessions os
    JOIN users u ON os.user_id = u.id
    WHERE os.id = p_session_id;
    
    IF v_user_id IS NULL THEN
        RETURN FALSE;
    END IF;
    
    -- Deduct from user balance
    UPDATE users 
    SET balance_cents = balance_cents - (v_payout_amount * 100)::INTEGER
    WHERE id = v_user_id;
    
    -- Mark session as processed
    UPDATE objective_sessions
    SET status = 'missed',
        payout_triggered = true,
        payout_amount = v_payout_amount,
        payout_transaction_id = p_transaction_id,
        updated_at = NOW()
    WHERE id = p_session_id;
    
    RETURN TRUE;
END;
$$;

-- 6. Drop and recreate endpoint helper: Get user's active recipient
DROP FUNCTION IF EXISTS get_user_recipient(UUID);
CREATE OR REPLACE FUNCTION get_user_recipient(p_user_id UUID)
RETURNS TABLE (
    recipient_id UUID,
    recipient_name VARCHAR,
    recipient_email VARCHAR,
    recipient_phone VARCHAR,
    is_active BOOLEAN,
    is_committed BOOLEAN
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT 
        r.id as recipient_id,
        r.full_name as recipient_name,
        r.email as recipient_email,
        r.phone as recipient_phone,
        true as is_active,
        u.destination_committed as is_committed
    FROM users u
    LEFT JOIN recipients r ON r.id = COALESCE(u.committed_recipient_id, u.custom_recipient_id)
    WHERE u.id = p_user_id
    AND r.id IS NOT NULL;
END;
$$;

-- 7. Enable RLS
ALTER TABLE objective_sessions ENABLE ROW LEVEL SECURITY;

-- Allow users to see their own sessions
DROP POLICY IF EXISTS "Users can view own sessions" ON objective_sessions;
CREATE POLICY "Users can view own sessions" ON objective_sessions
    FOR SELECT USING (auth.uid()::text = user_id::text OR true);

-- Allow system to manage sessions
DROP POLICY IF EXISTS "System can manage sessions" ON objective_sessions;
CREATE POLICY "System can manage sessions" ON objective_sessions
    FOR ALL USING (true);

-- 8. Helper function to deduct user balance
DROP FUNCTION IF EXISTS deduct_user_balance(UUID, INTEGER);
CREATE OR REPLACE FUNCTION deduct_user_balance(
    p_user_id UUID,
    p_amount_cents INTEGER
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE users 
    SET balance_cents = COALESCE(balance_cents, 0) - p_amount_cents,
        updated_at = NOW()
    WHERE id = p_user_id;
    
    RETURN FOUND;
END;
$$;

-- Verify setup
SELECT 'Payout system setup complete!' as status;
