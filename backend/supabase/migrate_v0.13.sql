-- Migration v0.13: Webhook event filter support
-- Date: 2026-04-16

-- Add webhook_event_filter column (JSONB) to user_settings
-- Format: { "severities": ["Critical","Warning"], "types": ["cost_spike"], "providers": ["Claude"] }
-- NULL = no filter (send all alerts)

ALTER TABLE public.user_settings
  ADD COLUMN IF NOT EXISTS webhook_event_filter jsonb DEFAULT NULL;

COMMENT ON COLUMN public.user_settings.webhook_event_filter IS
  'Optional JSON filter for webhook alerts: { severities?, types?, providers? }';
