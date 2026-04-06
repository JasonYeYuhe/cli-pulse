-- ============================================================
-- CLI Pulse — Migration v0.8
-- Webhook integration: URL + enabled flag on user_settings
-- ============================================================

ALTER TABLE public.user_settings
  ADD COLUMN IF NOT EXISTS webhook_url text,
  ADD COLUMN IF NOT EXISTS webhook_enabled boolean NOT NULL DEFAULT false;

-- Index for quick lookup during alert dispatch
CREATE INDEX IF NOT EXISTS idx_user_settings_webhook_enabled
  ON public.user_settings(user_id)
  WHERE webhook_enabled = true AND webhook_url IS NOT NULL;
