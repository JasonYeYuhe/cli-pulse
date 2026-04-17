-- Migration v0.14: Cost-to-Code Yield Score
-- Date: 2026-04-17
-- Adds: project_hash on sessions; commits, session_commit_links, yield_score_daily tables;
--       ingest_commits + recompute_yield_scores_for_user RPC functions.
-- Codex-reviewed; uses normalized attribution (sum of weights per commit = 1.0).

-- 1. Add project_hash to sessions (NULL backwards-compatible for existing rows)
ALTER TABLE public.sessions ADD COLUMN IF NOT EXISTS project_hash TEXT;
CREATE INDEX IF NOT EXISTS sessions_user_project_active_idx
  ON public.sessions (user_id, project_hash, last_active_at DESC);

-- 2. Commits collected by helper daemon. We intentionally store NO message,
--    diff, path, or author email — only a per-user salted HMAC of the project path.
CREATE TABLE IF NOT EXISTS public.commits (
  id TEXT PRIMARY KEY,                          -- "{user_id}:{commit_hash}"
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  commit_hash TEXT NOT NULL,                    -- SHA1 from git
  project_hash TEXT NOT NULL,                   -- HMAC-SHA256(user_secret, abs_path)
  committed_at TIMESTAMPTZ NOT NULL,
  is_merge BOOLEAN NOT NULL DEFAULT false,      -- excluded from yield attribution
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, commit_hash)
);
CREATE INDEX IF NOT EXISTS commits_user_time_idx ON public.commits (user_id, committed_at DESC);

-- 3. Session ↔ commit link table with normalized weight per commit (sum = 1.0).
CREATE TABLE IF NOT EXISTS public.session_commit_links (
  session_id TEXT NOT NULL,
  commit_id TEXT NOT NULL REFERENCES public.commits(id) ON DELETE CASCADE,
  weight REAL NOT NULL CHECK (weight > 0 AND weight <= 1),
  is_ambiguous BOOLEAN NOT NULL DEFAULT false,  -- true if no candidate dominates (top weight < 0.6)
  linked_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (session_id, commit_id)
);
CREATE INDEX IF NOT EXISTS session_commit_links_session_idx ON public.session_commit_links (session_id);
CREATE INDEX IF NOT EXISTS session_commit_links_commit_idx ON public.session_commit_links (commit_id);

-- 4. Daily yield score rollup (avoids querying raw join in production).
CREATE TABLE IF NOT EXISTS public.yield_score_daily (
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  provider TEXT NOT NULL,
  day DATE NOT NULL,
  total_cost NUMERIC(10,4) NOT NULL DEFAULT 0,
  weighted_commit_count NUMERIC(10,4) NOT NULL DEFAULT 0,
  raw_commit_count INTEGER NOT NULL DEFAULT 0,
  ambiguous_commit_count INTEGER NOT NULL DEFAULT 0,
  last_recomputed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, provider, day)
);

-- 5. RLS
ALTER TABLE public.commits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.session_commit_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.yield_score_daily ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS commits_owner ON public.commits;
CREATE POLICY commits_owner ON public.commits FOR ALL USING (user_id = auth.uid());

DROP POLICY IF EXISTS session_commit_links_owner ON public.session_commit_links;
CREATE POLICY session_commit_links_owner ON public.session_commit_links FOR ALL
  USING (EXISTS (SELECT 1 FROM public.commits c WHERE c.id = commit_id AND c.user_id = auth.uid()));

DROP POLICY IF EXISTS yield_score_daily_owner ON public.yield_score_daily;
CREATE POLICY yield_score_daily_owner ON public.yield_score_daily FOR ALL USING (user_id = auth.uid());

-- 6. Recompute function (called automatically by ingest_commits).
--    Splits session-cost aggregation from commit-link aggregation to avoid
--    double-counting estimated_cost when a session links to multiple commits.
CREATE OR REPLACE FUNCTION public.recompute_yield_scores_for_user(p_user_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  DELETE FROM public.yield_score_daily WHERE user_id = p_user_id;

  WITH session_costs AS (
    SELECT s.id, s.provider, s.estimated_cost, date_trunc('day', s.last_active_at)::date AS day
    FROM public.sessions s
    WHERE s.user_id = p_user_id
  ), session_weights AS (
    SELECT scl.session_id,
           SUM(scl.weight) AS weighted_commits,
           COUNT(*) AS raw_commits,
           SUM(CASE WHEN scl.is_ambiguous THEN 1 ELSE 0 END) AS ambiguous_commits
    FROM public.session_commit_links scl
    JOIN public.commits c ON c.id = scl.commit_id
    WHERE c.user_id = p_user_id
    GROUP BY scl.session_id
  )
  INSERT INTO public.yield_score_daily
    (user_id, provider, day, total_cost, weighted_commit_count, raw_commit_count, ambiguous_commit_count)
  SELECT
    p_user_id, sc.provider, sc.day,
    SUM(COALESCE(sc.estimated_cost, 0)),
    COALESCE(SUM(sw.weighted_commits), 0),
    COALESCE(SUM(sw.raw_commits)::int, 0),
    COALESCE(SUM(sw.ambiguous_commits)::int, 0)
  FROM session_costs sc
  LEFT JOIN session_weights sw ON sw.session_id = sc.id
  GROUP BY sc.provider, sc.day;
END;
$$;

-- 7. RPC: ingest_commits with normalized attribution.
--    For each commit, finds all candidate sessions (same project_hash + commit time
--    within session window), computes recency-based weights, normalizes them so
--    the total per-commit weight equals 1.0, and flags ambiguous commits where
--    no single session dominates (top weight < 0.6).
CREATE OR REPLACE FUNCTION public.ingest_commits(p_commits jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_commit jsonb;
  v_commit_id TEXT;
  v_committed_at TIMESTAMPTZ;
  v_project_hash TEXT;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  FOR v_commit IN SELECT * FROM jsonb_array_elements(p_commits) LOOP
    v_commit_id := v_user_id::text || ':' || (v_commit->>'commit_hash');
    v_committed_at := (v_commit->>'committed_at')::timestamptz;
    v_project_hash := v_commit->>'project_hash';

    INSERT INTO public.commits (id, user_id, commit_hash, project_hash, committed_at, is_merge)
    VALUES (v_commit_id, v_user_id, v_commit->>'commit_hash', v_project_hash, v_committed_at,
            COALESCE((v_commit->>'is_merge')::boolean, false))
    ON CONFLICT (user_id, commit_hash) DO NOTHING;

    -- Skip merge commits in attribution
    IF COALESCE((v_commit->>'is_merge')::boolean, false) THEN CONTINUE; END IF;

    -- Normalized attribution: each commit's total weight across sessions = 1.0
    WITH candidates AS (
      SELECT s.id AS session_id,
             GREATEST(0.05,
               1.0 - LEAST(1.0,
                 EXTRACT(EPOCH FROM ABS(v_committed_at - s.last_active_at)) / 1800.0
               )
             ) AS recency_score
      FROM public.sessions s
      WHERE s.user_id = v_user_id
        AND s.project_hash IS NOT NULL
        AND s.project_hash = v_project_hash
        AND v_committed_at BETWEEN s.started_at AND (s.last_active_at + interval '30 minutes')
    ), totals AS (
      SELECT SUM(recency_score) AS total_score FROM candidates
    ), normalized AS (
      SELECT c.session_id, (c.recency_score / t.total_score)::real AS weight
      FROM candidates c, totals t
      WHERE t.total_score > 0
    ), top_weight AS (
      SELECT MAX(weight) AS top FROM normalized
    )
    INSERT INTO public.session_commit_links (session_id, commit_id, weight, is_ambiguous)
    SELECT n.session_id, v_commit_id, n.weight,
           (SELECT top FROM top_weight) < 0.6
    FROM normalized n
    ON CONFLICT (session_id, commit_id) DO NOTHING;
  END LOOP;

  PERFORM public.recompute_yield_scores_for_user(v_user_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.ingest_commits(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.recompute_yield_scores_for_user(UUID) TO authenticated;
