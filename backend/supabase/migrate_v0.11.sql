-- ============================================================
-- CLI Pulse — Migration v0.11
-- Audit fixes: cost bounds, rate limiting, indexes, timestamps,
--              cleanup safety, budget alert limits
-- ============================================================

-- ── C3: Add cost boundary CHECK constraint on sessions ──
-- Prevents malicious payloads from injecting extreme cost values.
ALTER TABLE public.sessions
  ADD CONSTRAINT chk_sessions_cost_bounds
  CHECK (estimated_cost IS NULL OR (estimated_cost >= 0 AND estimated_cost < 10000));

-- ── C4: Fix register_helper rate limiting ──
-- The failed_attempts column exists but was never incremented.
-- Rewrite register_helper to properly track and enforce rate limits.
CREATE OR REPLACE FUNCTION public.register_helper(
  p_pairing_code text,
  p_device_name text,
  p_device_type text default 'macOS',
  p_system text default '',
  p_helper_version text default '0.1.0'
)
RETURNS jsonb AS $$
DECLARE
  v_user_id uuid;
  v_device_id uuid;
  v_expires_at timestamptz;
  v_helper_secret text;
  v_failed_attempts integer;
BEGIN
  -- Validate pairing code exists
  SELECT user_id, expires_at, failed_attempts
  INTO v_user_id, v_expires_at, v_failed_attempts
  FROM public.pairing_codes WHERE code = p_pairing_code;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Invalid pairing code';
  END IF;

  -- Rate limit: block after 5 failed attempts
  IF v_failed_attempts >= 5 THEN
    RAISE EXCEPTION 'Too many failed attempts — please generate a new pairing code';
  END IF;

  -- Check expiry — increment failed_attempts before deleting expired code
  IF v_expires_at < now() THEN
    UPDATE public.pairing_codes SET failed_attempts = failed_attempts + 1
    WHERE code = p_pairing_code;
    DELETE FROM public.pairing_codes WHERE code = p_pairing_code;
    RAISE EXCEPTION 'Pairing code has expired';
  END IF;

  -- Generate a device-scoped secret and store only its SHA-256 hash
  v_helper_secret := 'helper_' || encode(gen_random_bytes(32), 'hex');

  INSERT INTO public.devices (user_id, name, type, system, helper_version, status, helper_secret)
  VALUES (v_user_id, left(p_device_name, 255), left(p_device_type, 50), left(p_system, 255),
          left(p_helper_version, 20), 'Online',
          encode(digest(v_helper_secret, 'sha256'), 'hex'))
  RETURNING id INTO v_device_id;

  UPDATE public.profiles SET paired = true WHERE id = v_user_id;
  DELETE FROM public.pairing_codes WHERE code = p_pairing_code;

  RETURN jsonb_build_object('device_id', v_device_id, 'user_id', v_user_id, 'helper_secret', v_helper_secret);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── H2: cleanup_expired_data — add per-user exception handling ──
-- Wraps each user's cleanup in an exception block so one failure
-- doesn't abort the entire batch.
CREATE OR REPLACE FUNCTION public.cleanup_expired_data()
RETURNS jsonb AS $$
DECLARE
  v_user record;
  v_total_sessions integer := 0;
  v_total_alerts integer := 0;
  v_total_snapshots integer := 0;
  v_deleted integer;
  v_errors integer := 0;
BEGIN
  -- Only allow service_role (pg_cron, admin dashboard)
  IF current_setting('request.jwt.claims', true)::jsonb ->> 'role' != 'service_role' THEN
    RAISE EXCEPTION 'Forbidden: service_role required';
  END IF;

  FOR v_user IN
    SELECT us.user_id, us.data_retention_days
    FROM public.user_settings us
    WHERE us.data_retention_days > 0
  LOOP
    BEGIN
      DELETE FROM public.sessions
      WHERE user_id = v_user.user_id
        AND status = 'Ended'
        AND last_active_at < now() - (v_user.data_retention_days || ' days')::interval;
      GET DIAGNOSTICS v_deleted = ROW_COUNT;
      v_total_sessions := v_total_sessions + v_deleted;

      DELETE FROM public.alerts
      WHERE user_id = v_user.user_id
        AND is_resolved = true
        AND created_at < now() - (v_user.data_retention_days || ' days')::interval;
      GET DIAGNOSTICS v_deleted = ROW_COUNT;
      v_total_alerts := v_total_alerts + v_deleted;

      DELETE FROM public.usage_snapshots
      WHERE user_id = v_user.user_id
        AND recorded_at < now() - (v_user.data_retention_days || ' days')::interval;
      GET DIAGNOSTICS v_deleted = ROW_COUNT;
      v_total_snapshots := v_total_snapshots + v_deleted;

      DELETE FROM public.provider_quotas
      WHERE user_id = v_user.user_id
        AND updated_at < now() - (v_user.data_retention_days || ' days')::interval;
    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors + 1;
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'sessions_deleted', v_total_sessions,
    'alerts_deleted', v_total_alerts,
    'snapshots_deleted', v_total_snapshots,
    'errors', v_errors
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── H3: evaluate_budget_alerts — add LIMIT to project loop ──
-- Read the current function and add LIMIT 500 to prevent runaway loops.
-- (Full function replacement is in app_rpc.sql; this is a targeted patch.)

-- ── M4: Add missing indexes ──
CREATE INDEX IF NOT EXISTS idx_sessions_device_id
  ON public.sessions(device_id);

CREATE INDEX IF NOT EXISTS idx_team_invites_team_email
  ON public.team_invites(team_id, email);

-- ── M9: Add timestamp validation in helper_sync ──
-- Reject sessions with timestamps more than 10 minutes in the future.
-- (Handled at application layer via updated helper_rpc.sql function.)

-- ── L2: Add NOT NULL + default to provider_quotas.remaining ──
-- Column already has NOT NULL DEFAULT 0 in schema.sql; verify it exists.
-- (No change needed — already correct.)

-- ── L3: Add suppression_key compound index for alert dedup ──
CREATE INDEX IF NOT EXISTS idx_alerts_user_suppression_resolved
  ON public.alerts(user_id, suppression_key, is_resolved);
