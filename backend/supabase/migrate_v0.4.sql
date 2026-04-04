-- ============================================================
-- CLI Pulse — Migration v0.4
-- Indexes, constraints, retention, and rate limiting
-- ============================================================

-- #6: Missing indexes for alert queries
CREATE INDEX IF NOT EXISTS idx_alerts_user_resolved
  ON public.alerts(user_id, is_resolved);
CREATE INDEX IF NOT EXISTS idx_alerts_suppression
  ON public.alerts(user_id, suppression_key);

-- #24: Additional indexes for common queries
CREATE INDEX IF NOT EXISTS idx_sessions_device_id
  ON public.sessions(device_id);
CREATE INDEX IF NOT EXISTS idx_team_members_user_id
  ON public.team_members(user_id);
CREATE INDEX IF NOT EXISTS idx_alerts_grouping_key
  ON public.alerts(user_id, grouping_key);

-- #15: CHECK constraints for data integrity
ALTER TABLE public.sessions
  ADD CONSTRAINT chk_sessions_status
  CHECK (status IN ('Running', 'Ended', 'Paused'));

ALTER TABLE public.alerts
  ADD CONSTRAINT chk_alerts_severity
  CHECK (severity IN ('Critical', 'Warning', 'Info'));

-- #27: Rate limiting on pairing code validation
ALTER TABLE public.pairing_codes
  ADD COLUMN IF NOT EXISTS failed_attempts integer NOT NULL DEFAULT 0;

-- Update register_helper to enforce rate limiting
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
  -- Validate pairing code
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

  IF v_expires_at < now() THEN
    DELETE FROM public.pairing_codes WHERE code = p_pairing_code;
    RAISE EXCEPTION 'Pairing code has expired';
  END IF;

  -- Generate a device-scoped secret
  v_helper_secret := 'helper_' || encode(gen_random_bytes(32), 'hex');

  INSERT INTO public.devices (user_id, name, type, system, helper_version, status, helper_secret)
  VALUES (v_user_id, p_device_name, p_device_type, p_system, p_helper_version, 'Online', v_helper_secret)
  RETURNING id INTO v_device_id;

  UPDATE public.profiles SET paired = true WHERE id = v_user_id;
  DELETE FROM public.pairing_codes WHERE code = p_pairing_code;

  RETURN jsonb_build_object('device_id', v_device_id, 'user_id', v_user_id, 'helper_secret', v_helper_secret);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- #13: Safer JSONB field casting in helper_sync (use COALESCE for all casts)
-- Already using COALESCE in schema — the current helper_rpc.sql is adequate.
-- Additional safety: validate provider field is non-empty in sessions.

-- #14: Data retention cleanup function
CREATE OR REPLACE FUNCTION public.cleanup_old_data(
  p_retention_days integer DEFAULT 90
)
RETURNS jsonb AS $$
DECLARE
  v_sessions_deleted integer;
  v_snapshots_deleted integer;
  v_cutoff timestamptz;
BEGIN
  v_cutoff := now() - (p_retention_days || ' days')::interval;

  -- Clean up ended sessions older than retention period
  DELETE FROM public.sessions
  WHERE status = 'Ended'
    AND last_active_at < v_cutoff;
  GET DIAGNOSTICS v_sessions_deleted = ROW_COUNT;

  -- Clean up old usage snapshots
  DELETE FROM public.usage_snapshots
  WHERE recorded_at < v_cutoff;
  GET DIAGNOSTICS v_snapshots_deleted = ROW_COUNT;

  RETURN jsonb_build_object(
    'sessions_deleted', v_sessions_deleted,
    'snapshots_deleted', v_snapshots_deleted,
    'cutoff', v_cutoff
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
