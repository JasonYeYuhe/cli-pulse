-- ============================================================
-- CLI Pulse — Helper RPC Functions
-- Called by the helper daemon via Supabase anon key + PostgREST
-- All functions use security definer to bypass RLS
-- ============================================================

-- Register a helper device via pairing code
create or replace function public.register_helper(
  p_pairing_code text,
  p_device_name text,
  p_device_type text default 'macOS',
  p_system text default '',
  p_helper_version text default '0.1.0'
)
returns jsonb as $$
declare
  v_user_id uuid;
  v_device_id uuid;
  v_expires_at timestamptz;
begin
  select user_id, expires_at into v_user_id, v_expires_at
  from public.pairing_codes where code = p_pairing_code;

  if v_user_id is null then
    raise exception 'Invalid pairing code';
  end if;

  if v_expires_at < now() then
    delete from public.pairing_codes where code = p_pairing_code;
    raise exception 'Pairing code has expired';
  end if;

  insert into public.devices (user_id, name, type, system, helper_version, status)
  values (v_user_id, p_device_name, p_device_type, p_system, p_helper_version, 'Online')
  returning id into v_device_id;

  update public.profiles set paired = true where id = v_user_id;
  delete from public.pairing_codes where code = p_pairing_code;

  return jsonb_build_object('device_id', v_device_id, 'user_id', v_user_id);
end;
$$ language plpgsql security definer;

-- Helper heartbeat
create or replace function public.helper_heartbeat(
  p_device_id uuid,
  p_user_id uuid,
  p_cpu_usage integer default 0,
  p_memory_usage integer default 0,
  p_active_session_count integer default 0
)
returns jsonb as $$
declare
  v_found boolean;
begin
  select true into v_found
  from public.devices where id = p_device_id and user_id = p_user_id;

  if not v_found then
    raise exception 'Device not found or unauthorized';
  end if;

  update public.devices set
    status = 'Online', cpu_usage = p_cpu_usage,
    memory_usage = p_memory_usage, last_seen_at = now()
  where id = p_device_id and user_id = p_user_id;

  return jsonb_build_object('status', 'ok');
end;
$$ language plpgsql security definer;

-- Helper sync — upsert sessions, alerts, provider quotas
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
    insert into public.sessions (id, user_id, device_id, name, provider, project, status, total_usage, estimated_cost, requests, error_count, started_at, last_active_at, synced_at)
    values (
      v_session->>'id', p_user_id, p_device_id,
      coalesce(v_session->>'name', ''), v_session->>'provider',
      coalesce(v_session->>'project', ''), coalesce(v_session->>'status', 'Running'),
      coalesce((v_session->>'total_usage')::integer, 0),
      (v_session->>'exact_cost')::numeric,
      coalesce((v_session->>'requests')::integer, 0),
      coalesce((v_session->>'error_count')::integer, 0),
      coalesce((v_session->>'started_at')::timestamptz, now()),
      coalesce((v_session->>'last_active_at')::timestamptz, now()), now()
    )
    on conflict (id, user_id) do update set
      name = excluded.name, status = excluded.status,
      total_usage = excluded.total_usage, estimated_cost = excluded.estimated_cost,
      requests = excluded.requests, error_count = excluded.error_count,
      last_active_at = excluded.last_active_at, synced_at = now();
    v_session_count := v_session_count + 1;
  end loop;

  for v_alert in select * from jsonb_array_elements(p_alerts) loop
    insert into public.alerts (id, user_id, type, severity, title, message, related_project_id, related_project_name, related_session_id, related_session_name, related_provider, related_device_name, created_at)
    values (
      v_alert->>'id', p_user_id, v_alert->>'type',
      coalesce(v_alert->>'severity', 'Info'), v_alert->>'title',
      coalesce(v_alert->>'message', ''),
      v_alert->>'related_project_id', v_alert->>'related_project_name',
      v_alert->>'related_session_id', v_alert->>'related_session_name',
      v_alert->>'related_provider', v_alert->>'related_device_name',
      coalesce((v_alert->>'created_at')::timestamptz, now())
    )
    on conflict (id, user_id) do update set
      severity = excluded.severity, title = excluded.title, message = excluded.message;
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
