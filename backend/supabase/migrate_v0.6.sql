-- ============================================================
-- CLI Pulse — Migration v0.6
-- Google Play Billing support for subscriptions table
-- ============================================================

-- Google Play order ID for anti-replay checks
ALTER TABLE public.subscriptions
  ADD COLUMN IF NOT EXISTS play_order_id text;

-- Platform discriminator (apple or google)
ALTER TABLE public.subscriptions
  ADD COLUMN IF NOT EXISTS platform text NOT NULL DEFAULT 'apple';

-- Index for anti-replay lookups on Google Play orders
CREATE INDEX IF NOT EXISTS idx_subscriptions_play_order_id
  ON public.subscriptions(play_order_id)
  WHERE play_order_id IS NOT NULL;
