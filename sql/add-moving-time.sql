-- Add moving_time_seconds to objective_sessions so we can track
-- actual Strava running time per day (accumulated across multiple runs).
ALTER TABLE objective_sessions
    ADD COLUMN IF NOT EXISTS moving_time_seconds INT NOT NULL DEFAULT 0;
