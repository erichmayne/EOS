-- Competitions feature tables (FULL SCHEMA)
-- Run this in Supabase SQL Editor

-- Main competitions table
CREATE TABLE IF NOT EXISTS competitions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    creator_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    objective_type TEXT NOT NULL CHECK (objective_type IN ('pushups', 'run', 'both')),
    scoring_type TEXT NOT NULL DEFAULT 'consistency' CHECK (scoring_type IN ('consistency', 'cumulative')),
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'active', 'completed')),
    invite_code TEXT NOT NULL UNIQUE,
    target_value NUMERIC NOT NULL DEFAULT 0,
    buy_in_amount NUMERIC NOT NULL DEFAULT 0,
    duration_days INT NOT NULL DEFAULT 7,
    winner_user_id UUID REFERENCES users(id),
    payout_completed BOOLEAN NOT NULL DEFAULT false,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Competition participants
CREATE TABLE IF NOT EXISTS competition_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    competition_id UUID NOT NULL REFERENCES competitions(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'withdrawn')),
    buy_in_locked BOOLEAN NOT NULL DEFAULT false,
    buy_in_amount NUMERIC NOT NULL DEFAULT 0,
    UNIQUE(competition_id, user_id)
);

-- Payout audit log
CREATE TABLE IF NOT EXISTS competition_payouts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    competition_id UUID NOT NULL REFERENCES competitions(id) ON DELETE CASCADE,
    winner_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    pool_amount NUMERIC NOT NULL,
    participant_count INT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes for fast lookups
CREATE INDEX IF NOT EXISTS idx_competitions_invite_code ON competitions(invite_code);
CREATE INDEX IF NOT EXISTS idx_competitions_status ON competitions(status);
CREATE INDEX IF NOT EXISTS idx_competition_participants_user ON competition_participants(user_id);
CREATE INDEX IF NOT EXISTS idx_competition_participants_comp ON competition_participants(competition_id);
CREATE INDEX IF NOT EXISTS idx_competition_payouts_comp ON competition_payouts(competition_id);
