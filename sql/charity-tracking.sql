-- Charity Tracking System
-- Run in Supabase SQL Editor

-- 1. Add committed_charity column to users table
ALTER TABLE users ADD COLUMN IF NOT EXISTS committed_charity VARCHAR(255);

-- 2. Create charity_payouts table to track individual charity payouts
CREATE TABLE IF NOT EXISTS charity_payouts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    charity_name VARCHAR(255) NOT NULL,
    amount_cents INTEGER NOT NULL,
    session_id UUID REFERENCES objective_sessions(id),
    status VARCHAR(20) DEFAULT 'pending', -- pending, aggregated, paid_out
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Create index for efficient queries
CREATE INDEX IF NOT EXISTS idx_charity_payouts_charity ON charity_payouts(charity_name);
CREATE INDEX IF NOT EXISTS idx_charity_payouts_status ON charity_payouts(status);
CREATE INDEX IF NOT EXISTS idx_charity_payouts_user ON charity_payouts(user_id);

-- 4. Create view for charity totals (aggregated amounts per charity)
CREATE OR REPLACE VIEW charity_totals AS
SELECT 
    charity_name,
    COUNT(*) as payout_count,
    SUM(amount_cents) as total_cents,
    SUM(amount_cents) / 100.0 as total_dollars,
    COUNT(DISTINCT user_id) as unique_users,
    SUM(CASE WHEN status = 'pending' THEN amount_cents ELSE 0 END) as pending_cents,
    SUM(CASE WHEN status = 'paid_out' THEN amount_cents ELSE 0 END) as paid_out_cents
FROM charity_payouts
GROUP BY charity_name
ORDER BY total_cents DESC;

-- 5. Enable RLS on charity_payouts
ALTER TABLE charity_payouts ENABLE ROW LEVEL SECURITY;

-- Allow system to manage
CREATE POLICY "System manages charity payouts" ON charity_payouts
    FOR ALL USING (true);

-- 6. Function to record a charity payout
CREATE OR REPLACE FUNCTION record_charity_payout(
    p_user_id UUID,
    p_charity_name VARCHAR,
    p_amount_cents INTEGER,
    p_session_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_payout_id UUID;
BEGIN
    INSERT INTO charity_payouts (user_id, charity_name, amount_cents, session_id, status)
    VALUES (p_user_id, p_charity_name, p_amount_cents, p_session_id, 'pending')
    RETURNING id INTO v_payout_id;
    
    RETURN v_payout_id;
END;
$$;

-- Verify
SELECT 'Charity tracking system ready!' as status;
