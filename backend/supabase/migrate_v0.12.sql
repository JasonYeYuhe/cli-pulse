-- Migration v0.12: Security & performance improvements
-- Date: 2026-04-09

-- ── Missing indexes for query performance ──

-- team_invites: composite index for invite lookup by team + email
CREATE INDEX IF NOT EXISTS idx_team_invites_team_email
  ON public.team_invites(team_id, email);

-- alerts: index for webhook dedup lookups
CREATE INDEX IF NOT EXISTS idx_alerts_user_suppression_created
  ON public.alerts(user_id, suppression_key, created_at DESC);
