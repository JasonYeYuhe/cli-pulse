-- ============================================================
-- CLI Pulse — Rollback v0.4
-- Reverses: indexes, constraints, rate limiting, retention function
-- Prerequisites: v0.4 migration was applied
-- ============================================================

-- Remove indexes added in v0.4
DROP INDEX IF EXISTS idx_alerts_user_resolved;
DROP INDEX IF EXISTS idx_alerts_suppression;
DROP INDEX IF EXISTS idx_sessions_device_id;
DROP INDEX IF EXISTS idx_team_members_user_id;
DROP INDEX IF EXISTS idx_alerts_grouping_key;

-- Remove CHECK constraints
ALTER TABLE public.sessions DROP CONSTRAINT IF EXISTS chk_sessions_status;
ALTER TABLE public.alerts DROP CONSTRAINT IF EXISTS chk_alerts_severity;

-- Remove rate limiting column from pairing_codes
ALTER TABLE public.pairing_codes DROP COLUMN IF EXISTS failed_attempts;

-- Restore register_helper without rate limiting (v0.3 version)
-- Re-apply helper_rpc.sql from the v0.3 commit to restore original function

-- Remove data retention function
DROP FUNCTION IF EXISTS public.cleanup_old_data(integer);
