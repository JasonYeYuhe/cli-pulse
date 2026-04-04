-- ============================================================
-- CLI Pulse — Rollback v0.2
-- Reverses: collection_confidence, alert grouping columns
-- Prerequisites: v0.2 migration was applied, v0.3 rollback already run
-- WARNING: This removes data stored in these columns
-- ============================================================

-- Remove collection_confidence from sessions
ALTER TABLE public.sessions DROP COLUMN IF EXISTS collection_confidence;

-- Remove alert grouping/deep-link columns
ALTER TABLE public.alerts
  DROP COLUMN IF EXISTS source_kind,
  DROP COLUMN IF EXISTS source_id,
  DROP COLUMN IF EXISTS grouping_key,
  DROP COLUMN IF EXISTS suppression_key;

-- Restore helper_sync to v0.1 version (without collection_confidence or grouping fields)
-- Re-apply the original helper_rpc.sql from before v0.2
