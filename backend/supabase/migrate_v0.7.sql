-- ============================================================
-- CLI Pulse — Migration v0.7
-- Google Play purchase token support + anti-replay indexes
-- ============================================================

-- Google Play purchase token for anti-replay fallback
ALTER TABLE public.subscriptions
  ADD COLUMN IF NOT EXISTS play_purchase_token text;

-- Unique anti-replay indexes (prevent same purchase across accounts)
CREATE UNIQUE INDEX IF NOT EXISTS idx_sub_apple_txn
  ON public.subscriptions(apple_original_transaction_id)
  WHERE apple_original_transaction_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_sub_play_order
  ON public.subscriptions(play_order_id)
  WHERE play_order_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_sub_play_token
  ON public.subscriptions(play_purchase_token)
  WHERE play_purchase_token IS NOT NULL;

-- profiles columns for receipt tracking (added in schema.sql)
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS receipt_verified_at timestamptz;
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS last_transaction_id text;

-- Session/alert ID length constraints
ALTER TABLE public.sessions
  ADD CONSTRAINT sessions_id_length CHECK (length(id) <= 128);
ALTER TABLE public.alerts
  ADD CONSTRAINT alerts_id_length CHECK (length(id) <= 128);
