-- ============================================================
-- CLI Pulse — Migration v0.5
-- Server-side receipt validation columns on profiles
-- ============================================================

-- Track when the last server-side receipt verification occurred
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS receipt_verified_at timestamptz;

-- Store the last verified StoreKit 2 transaction ID
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS last_transaction_id text;

-- Index for querying unverified paid users (tier != 'free' but never verified)
CREATE INDEX IF NOT EXISTS idx_profiles_receipt_verification
  ON public.profiles(tier, receipt_verified_at)
  WHERE tier != 'free';
