-- =================================================================
-- Cleanup: stop auto-assigning the 50-pushup objective to new users.
-- =================================================================
--
-- Background: users.objective_count had `DEFAULT 50` baked into the schema
-- from the early single-objective era, so every new user was silently given
-- a 50-pushup target. Combined with backend "legacy fallback" code paths
-- that read users.objective_count when no user_objectives row exists, this
-- caused every new account to show a 50-pushup objective on the home
-- screen even though pushups were never selected during onboarding.
--
-- This migration:
--   1. Removes the column default so new users no longer auto-receive 50.
--   2. Nulls out objective_count / objective_type for any user that does
--      NOT have an enabled pushups row in user_objectives (those users
--      never explicitly opted into pushups).
--   3. Deletes orphaned pushup objective_sessions for users without an
--      enabled pushups objective so the home screen stops showing them.
--
-- Idempotent and safe to run multiple times.
-- =================================================================

-- 1. Drop the column default (new users get NULL going forward).
ALTER TABLE users ALTER COLUMN objective_count DROP DEFAULT;

-- 2. Drop the legacy objective_type default ('pushups') so it doesn't
--    quietly mark new users as pushup users.
ALTER TABLE users ALTER COLUMN objective_type DROP DEFAULT;

-- 3. Null out the legacy fields for users WITHOUT a real pushups objective.
--    Anyone who actually wants pushups will already have a row in
--    user_objectives (created either via the original migration or via
--    /objectives/settings/:userId).
UPDATE users
SET
    objective_count = NULL,
    objective_type = NULL
WHERE id NOT IN (
    SELECT user_id
    FROM user_objectives
    WHERE objective_type = 'pushups'
      AND enabled = true
      AND target_value > 0
);

-- 4. Remove orphaned pushup sessions for users who don't have an enabled
--    pushups objective. These are the rows that show up as "missing" on
--    the home screen even though the user never enabled pushups.
DELETE FROM objective_sessions
WHERE objective_type = 'pushups'
  AND user_id NOT IN (
      SELECT user_id
      FROM user_objectives
      WHERE objective_type = 'pushups'
        AND enabled = true
        AND target_value > 0
  );

-- =================================================================
-- After running this, redeploy the backend with the matching code
-- changes that remove the four `user.objective_count > 0` legacy
-- fallback paths in server.js.
-- =================================================================
