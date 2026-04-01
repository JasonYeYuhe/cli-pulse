-- ============================================================
-- CLI Pulse v0.3 Migration
-- Run against live Supabase to add helper_secret auth + tier quotas
-- Prerequisites: v0.2 migration already applied
-- ============================================================

-- Profiles: add tier override for admin grants
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS tier text NOT NULL DEFAULT 'free';

-- Devices: add helper_secret for device-scoped auth
ALTER TABLE public.devices
  ADD COLUMN IF NOT EXISTS helper_secret text;

-- Provider quotas: add tier columns for CodexBar-style bars
ALTER TABLE public.provider_quotas
  ADD COLUMN IF NOT EXISTS quota integer,
  ADD COLUMN IF NOT EXISTS plan_type text,
  ADD COLUMN IF NOT EXISTS reset_time timestamptz,
  ADD COLUMN IF NOT EXISTS tiers jsonb NOT NULL DEFAULT '[]'::jsonb;

-- Deploy all RPC functions (see helper_rpc.sql + app_rpc.sql for full source)
-- Must DROP first to change signatures and security mode

DROP FUNCTION IF EXISTS public.register_helper(text, text, text, text, text);
DROP FUNCTION IF EXISTS public.helper_heartbeat(uuid, text, integer, integer, integer);
DROP FUNCTION IF EXISTS public.helper_sync(uuid, uuid, jsonb, jsonb, jsonb);
DROP FUNCTION IF EXISTS public.helper_sync(uuid, text, jsonb, jsonb, jsonb);
DROP FUNCTION IF EXISTS public.helper_sync(uuid, text, jsonb, jsonb, jsonb, jsonb);
DROP FUNCTION IF EXISTS public.dashboard_summary();
DROP FUNCTION IF EXISTS public.provider_summary();
DROP FUNCTION IF EXISTS public.delete_user_account();

-- Then run the full contents of helper_rpc.sql and app_rpc.sql
-- (omitted here since they are the canonical source of truth)
