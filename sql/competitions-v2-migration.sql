-- Competitions V2 migration: lobby flow, balance, payouts, winner tracking
-- Run this in Supabase SQL Editor

-- Add winner tracking to competitions
ALTER TABLE competitions ADD COLUMN IF NOT EXISTS winner_user_id UUID REFERENCES users(id);
ALTER TABLE competitions ADD COLUMN IF NOT EXISTS payout_completed BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE competitions ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ;

-- Store duration so we can set start/end when creator hits "Start"
ALTER TABLE competitions ADD COLUMN IF NOT EXISTS duration_days INT NOT NULL DEFAULT 7;

-- Track buy-in status per participant
ALTER TABLE competition_participants ADD COLUMN IF NOT EXISTS buy_in_locked BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE competition_participants ADD COLUMN IF NOT EXISTS buy_in_amount NUMERIC NOT NULL DEFAULT 0;

-- Competition payout log (audit trail)
CREATE TABLE IF NOT EXISTS competition_payouts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    competition_id UUID NOT NULL REFERENCES competitions(id) ON DELETE CASCADE,
    winner_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    pool_amount NUMERIC NOT NULL,
    participant_count INT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_competition_payouts_comp ON competition_payouts(competition_id);
