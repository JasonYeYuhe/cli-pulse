-- ============================================================
-- CLI Pulse v0.2 Migration
-- Run this against the live Supabase database to add v0.2 columns
-- ============================================================

-- Sessions: add collection_confidence
alter table public.sessions
  add column if not exists collection_confidence text not null default 'medium';

-- Alerts: add deep link / grouping fields
alter table public.alerts
  add column if not exists source_kind text,
  add column if not exists source_id text,
  add column if not exists grouping_key text,
  add column if not exists suppression_key text;

-- Re-create helper_sync with v0.2 fields (see helper_rpc.sql for full source)
create or replace function public.helper_sync(
  p_device_id uuid,
  p_user_id uuid,
  p_sessions jsonb default '[]'::jsonb,
  p_alerts jsonb default '[]'::jsonb,
  p_provider_remaining jsonb default '{}'::jsonb
)
returns jsonb as $$
declare
  v_found boolean;
  v_session jsonb;
  v_alert jsonb;
  v_provider text;
  v_remaining integer;
  v_session_count integer := 0;
  v_alert_count integer := 0;
begin
  select true into v_found
  from public.devices where id = p_device_id and user_id = p_user_id;

  if not v_found then
    raise exception 'Device not found or unauthorized';
  end if;

  update public.devices set status = 'Online', last_seen_at = now()
  where id = p_device_id;

  for v_session in select * from jsonb_array_elements(p_sessions) loop
    insert into public.sessions (id, user_id, device_id, name, provider, project, status, total_usage, estimated_cost, requests, error_count, collection_confidence, started_at, last_active_at, synced_at)
    values (
      v_session->>'id', p_user_id, p_device_id,
      coalesce(v_session->>'name', ''), v_session->>'provider',
      coalesce(v_session->>'project', ''), coalesce(v_session->>'status', 'Running'),
      coalesce((v_session->>'total_usage')::integer, 0),
      (v_session->>'exact_cost')::numeric,
      coalesce((v_session->>'requests')::integer, 0),
      coalesce((v_session->>'error_count')::integer, 0),
      coalesce(v_session->>'collection_confidence', 'medium'),
      coalesce((v_session->>'started_at')::timestamptz, now()),
      coalesce((v_session->>'last_active_at')::timestamptz, now()), now()
    )
    on conflict (id, user_id) do update set
      name = excluded.name, status = excluded.status,
      total_usage = excluded.total_usage, estimated_cost = excluded.estimated_cost,
      requests = excluded.requests, error_count = excluded.error_count,
      collection_confidence = excluded.collection_confidence,
      last_active_at = excluded.last_active_at, synced_at = now();
    v_session_count := v_session_count + 1;
  end loop;

  for v_alert in select * from jsonb_array_elements(p_alerts) loop
    insert into public.alerts (id, user_id, type, severity, title, message, related_project_id, related_project_name, related_session_id, related_session_name, related_provider, related_device_name, source_kind, source_id, grouping_key, suppression_key, created_at)
    values (
      v_alert->>'id', p_user_id, v_alert->>'type',
      coalesce(v_alert->>'severity', 'Info'), v_alert->>'title',
      coalesce(v_alert->>'message', ''),
      v_alert->>'related_project_id', v_alert->>'related_project_name',
      v_alert->>'related_session_id', v_alert->>'related_session_name',
      v_alert->>'related_provider', v_alert->>'related_device_name',
      v_alert->>'source_kind', v_alert->>'source_id',
      v_alert->>'grouping_key', v_alert->>'suppression_key',
      coalesce((v_alert->>'created_at')::timestamptz, now())
    )
    on conflict (id, user_id) do update set
      severity = excluded.severity, title = excluded.title, message = excluded.message,
      source_kind = excluded.source_kind, source_id = excluded.source_id,
      grouping_key = excluded.grouping_key, suppression_key = excluded.suppression_key;
    v_alert_count := v_alert_count + 1;
  end loop;

  for v_provider, v_remaining in select * from jsonb_each_text(p_provider_remaining) loop
    insert into public.provider_quotas (user_id, provider, remaining, updated_at)
    values (p_user_id, v_provider, v_remaining::integer, now())
    on conflict (user_id, provider) do update set
      remaining = excluded.remaining, updated_at = now();
  end loop;

  return jsonb_build_object('sessions_synced', v_session_count, 'alerts_synced', v_alert_count);
end;
$$ language plpgsql security definer;
