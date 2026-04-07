-- ============================================================
-- CLI Pulse v1.5 — Daily Usage Metrics (migrate_v0.9)
-- Stores precise per-day per-model token counts and costs
-- from CostUsageScanner JSONL log parsing.
-- ============================================================

-- ── Daily Usage Metrics table ──
CREATE TABLE IF NOT EXISTS public.daily_usage_metrics (
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    metric_date DATE NOT NULL,
    provider TEXT NOT NULL,
    model TEXT NOT NULL,
    input_tokens BIGINT NOT NULL DEFAULT 0,
    cached_tokens BIGINT NOT NULL DEFAULT 0,
    output_tokens BIGINT NOT NULL DEFAULT 0,
    cost NUMERIC(10,6) NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, metric_date, provider, model)
);

ALTER TABLE public.daily_usage_metrics ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users own metrics"
    ON public.daily_usage_metrics
    FOR ALL USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_daily_usage_metrics_user_date
    ON public.daily_usage_metrics (user_id, metric_date DESC);

-- ── RPC: upsert_daily_usage ──
-- Batch upsert daily usage metrics from macOS scanner.
-- Input: JSON array of { metric_date, provider, model, input_tokens, cached_tokens, output_tokens, cost }
CREATE OR REPLACE FUNCTION public.upsert_daily_usage(metrics jsonb)
RETURNS jsonb AS $$
DECLARE
    v_user_id uuid := auth.uid();
    v_count int := 0;
    v_item jsonb;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(metrics)
    LOOP
        INSERT INTO public.daily_usage_metrics (
            user_id, metric_date, provider, model,
            input_tokens, cached_tokens, output_tokens, cost, updated_at
        ) VALUES (
            v_user_id,
            (v_item->>'metric_date')::date,
            v_item->>'provider',
            v_item->>'model',
            COALESCE((v_item->>'input_tokens')::bigint, 0),
            COALESCE((v_item->>'cached_tokens')::bigint, 0),
            COALESCE((v_item->>'output_tokens')::bigint, 0),
            COALESCE((v_item->>'cost')::numeric, 0),
            now()
        )
        ON CONFLICT (user_id, metric_date, provider, model)
        DO UPDATE SET
            input_tokens = EXCLUDED.input_tokens,
            cached_tokens = EXCLUDED.cached_tokens,
            output_tokens = EXCLUDED.output_tokens,
            cost = EXCLUDED.cost,
            updated_at = now();
        v_count := v_count + 1;
    END LOOP;

    RETURN jsonb_build_object('upserted', v_count);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── RPC: get_daily_usage ──
-- Returns the most recent N days of usage data for the authenticated user.
CREATE OR REPLACE FUNCTION public.get_daily_usage(days int DEFAULT 30)
RETURNS jsonb AS $$
DECLARE
    v_user_id uuid := auth.uid();
    v_since date := current_date - days;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    RETURN COALESCE(
        (SELECT jsonb_agg(row_to_json(t)) FROM (
            SELECT metric_date, provider, model,
                   input_tokens, cached_tokens, output_tokens, cost
            FROM public.daily_usage_metrics
            WHERE user_id = v_user_id AND metric_date >= v_since
            ORDER BY metric_date DESC, provider, model
        ) t),
        '[]'::jsonb
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
