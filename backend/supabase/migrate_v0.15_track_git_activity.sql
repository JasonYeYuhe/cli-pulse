-- Migration v0.15: Yield Score opt-in toggle
-- Date: 2026-04-17
-- Adds: user_settings.track_git_activity (default false; privacy-first)
--       get_track_git_activity RPC (helper authenticates by device + helper_secret)

ALTER TABLE public.user_settings
  ADD COLUMN IF NOT EXISTS track_git_activity BOOLEAN NOT NULL DEFAULT false;

-- Helper daemon needs to read this flag without a user JWT. Surface it via a
-- SECURITY DEFINER RPC that verifies the helper_secret first.
CREATE OR REPLACE FUNCTION public.get_track_git_activity(
  p_device_id uuid,
  p_helper_secret text
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_user_id uuid;
  v_flag boolean;
BEGIN
  SELECT user_id INTO v_user_id
  FROM public.devices
  WHERE id = p_device_id
    AND helper_secret = encode(digest(p_helper_secret, 'sha256'), 'hex');

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Device not found or unauthorized';
  END IF;

  SELECT COALESCE(track_git_activity, false) INTO v_flag
  FROM public.user_settings
  WHERE user_id = v_user_id;

  RETURN COALESCE(v_flag, false);
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_track_git_activity(uuid, text) TO anon, authenticated;
