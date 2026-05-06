-- ─────────────────────────────────────────────────────────────────────────────
-- Starter Comp + Balance Wall migration
--
-- Adds:
--  • Per-user state for the starter $10 promo bonus (locked until $50 earned)
--  • A flag on competitions to mark the auto-created starter race
--  • A nullable max_participants on competitions so the 1-runner solo race
--    can bypass the regular ≥2 minimum at start time
--
-- Backfill:
--  • All existing users default to starter_bonus_unlocked = true so historic
--    accounts aren't suddenly subject to a $50 wall they never opted into.
--    Only NEW signups (handled in backend) start with starter_bonus_unlocked = false.
--
-- Run in Supabase SQL editor.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── users ───────────────────────────────────────────────────────────────────
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS starter_bonus_amount   NUMERIC(10,2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS starter_bonus_unlocked BOOLEAN       NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS comp_earnings_total    NUMERIC(10,2) NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS starter_comp_id        UUID          NULL;

-- Backfill: any existing user is treated as if their bonus is already unlocked.
-- (Default value above already handles this for new rows; this guarantees it
-- for existing rows in case the default isn't applied retroactively.)
UPDATE users SET starter_bonus_unlocked = true WHERE starter_bonus_unlocked IS NULL;

-- ── competitions ────────────────────────────────────────────────────────────
ALTER TABLE competitions
    ADD COLUMN IF NOT EXISTS is_starter        BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS max_participants  INT     NULL;

-- Helpful index — we look up "does user X have a starter comp" on every signup
-- and on the home page.
CREATE INDEX IF NOT EXISTS idx_competitions_is_starter
    ON competitions(is_starter)
    WHERE is_starter = true;
