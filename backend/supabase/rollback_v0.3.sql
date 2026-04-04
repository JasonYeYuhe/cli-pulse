-- ============================================================
-- CLI Pulse — Rollback v0.3
-- Reverses: tier column, helper_secret, provider quota columns
-- Prerequisites: v0.3 migration was applied, v0.4 rollback already run
-- WARNING: This will drop helper_secret — all paired helpers will need re-pairing
-- ============================================================

-- Remove tier override from profiles
ALTER TABLE public.profiles DROP COLUMN IF EXISTS tier;

-- Remove helper_secret from devices (breaks all helper auth!)
ALTER TABLE public.devices DROP COLUMN IF EXISTS helper_secret;

-- Remove tier-related columns from provider_quotas
ALTER TABLE public.provider_quotas
  DROP COLUMN IF EXISTS quota,
  DROP COLUMN IF EXISTS plan_type,
  DROP COLUMN IF EXISTS reset_time,
  DROP COLUMN IF EXISTS tiers;

-- RPC functions must be restored to v0.2 versions
-- Re-apply helper_rpc.sql and app_rpc.sql from the v0.2 commit
-- The v0.3 migration dropped and recreated these functions with new signatures
