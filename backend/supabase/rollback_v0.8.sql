-- Rollback for migrate_v0.8.sql
-- Drops webhook columns (index cascades automatically)
ALTER TABLE public.user_settings DROP COLUMN IF EXISTS webhook_url;
ALTER TABLE public.user_settings DROP COLUMN IF EXISTS webhook_enabled;
