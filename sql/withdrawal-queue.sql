-- Withdrawal Queue System
-- Run this in Supabase SQL Editor

-- Create withdrawal_requests table
CREATE TABLE IF NOT EXISTS withdrawal_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    amount_cents INTEGER NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
    stripe_connect_account_id TEXT,
    payout_method TEXT CHECK (payout_method IN ('bank', 'card')),
    legal_name TEXT,
    dob JSONB,
    address JSONB,
    ssn_last4 TEXT,
    error_message TEXT,
    retry_count INTEGER DEFAULT 0,
    stripe_transfer_id TEXT,
    stripe_payout_id TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    processed_at TIMESTAMPTZ
);

-- Index for efficient queue processing
CREATE INDEX IF NOT EXISTS idx_withdrawal_requests_status ON withdrawal_requests(status);
CREATE INDEX IF NOT EXISTS idx_withdrawal_requests_user ON withdrawal_requests(user_id);
CREATE INDEX IF NOT EXISTS idx_withdrawal_requests_created ON withdrawal_requests(created_at);

-- Add trigger to update updated_at
CREATE OR REPLACE FUNCTION update_withdrawal_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS withdrawal_requests_updated_at ON withdrawal_requests;
CREATE TRIGGER withdrawal_requests_updated_at
    BEFORE UPDATE ON withdrawal_requests
    FOR EACH ROW
    EXECUTE FUNCTION update_withdrawal_updated_at();
