-- ============================================================
-- CLI Pulse — Migration v0.10
-- Push token support on devices table
-- ============================================================

ALTER TABLE public.devices
  ADD COLUMN IF NOT EXISTS push_token text,
  ADD COLUMN IF NOT EXISTS push_platform text;

-- Index for targeted push delivery
CREATE INDEX IF NOT EXISTS idx_devices_push_token
  ON public.devices(user_id)
  WHERE push_token IS NOT NULL;
