-- ============================================================
-- CLI Pulse — App RPC Functions
-- Called by the iOS/macOS/watchOS app via authenticated user JWT.
-- All use security definer so they bypass RLS with internal auth.
-- ============================================================

-- dashboard_summary: returns overview stats for the authenticated user
create or replace function public.dashboard_summary()
returns jsonb as $$
declare
  v_user_id uuid := auth.uid();
  v_today date := current_date;
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  -- Use range scan (SARGable) instead of casting to date for index efficiency
  select jsonb_build_object(
    'today_usage', coalesce((select sum(total_usage) from public.sessions where user_id = v_user_id and last_active_at >= v_today and last_active_at < v_today + interval '1 day'), 0),
    'today_cost', coalesce((select sum(estimated_cost) from public.sessions where user_id = v_user_id and last_active_at >= v_today and last_active_at < v_today + interval '1 day'), 0),
    'active_sessions', (select count(*) from public.sessions where user_id = v_user_id and status = 'Running'),
    'online_devices', (select count(*) from public.devices where user_id = v_user_id and status = 'Online'),
    'unresolved_alerts', (select count(*) from public.alerts where user_id = v_user_id and is_resolved = false),
    'today_sessions', coalesce((select sum(requests) from public.sessions where user_id = v_user_id and last_active_at >= v_today and last_active_at < v_today + interval '1 day'), 0)
  ) into v_result;

  return v_result;
end;
$$ language plpgsql security definer;

-- provider_summary: returns per-provider usage (week-scoped) for the authenticated user
create or replace function public.provider_summary()
returns jsonb as $$
declare
  v_user_id uuid := auth.uid();
  v_today date := current_date;
  v_week_start date := current_date - interval '7 days';
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  -- Single-pass: CTE aggregates sessions, then FULL OUTER JOIN with quotas
  return (
    with session_agg as (
      select
        s.provider,
        coalesce(sum(case when s.last_active_at >= v_today and s.last_active_at < v_today + interval '1 day' then s.total_usage else 0 end), 0) as today_usage,
        coalesce(sum(s.total_usage), 0) as total_usage,
        coalesce(sum(s.estimated_cost), 0) as estimated_cost
      from public.sessions s
      where s.user_id = v_user_id and s.last_active_at >= v_week_start
      group by s.provider
    )
    select coalesce(jsonb_agg(
      jsonb_build_object(
        'provider', coalesce(sa.provider, pq.provider),
        'today_usage', coalesce(sa.today_usage, 0),
        'total_usage', coalesce(sa.total_usage, 0),
        'estimated_cost', coalesce(sa.estimated_cost, 0),
        'remaining', pq.remaining,
        'quota', pq.quota,
        'plan_type', pq.plan_type,
        'reset_time', pq.reset_time,
        'tiers', coalesce(pq.tiers, '[]'::jsonb)
      ) order by coalesce(sa.total_usage, 0) desc
    ), '[]'::jsonb)
    from session_agg sa
    full outer join public.provider_quotas pq
      on pq.user_id = v_user_id and pq.provider = sa.provider
    where sa.provider is not null or pq.user_id = v_user_id
  );
end;
$$ language plpgsql security definer;

-- get_user_tier: returns the user's subscription tier (supports admin overrides)
create or replace function public.get_user_tier()
returns jsonb as $$
declare
  v_user_id uuid := auth.uid();
  v_tier text;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  -- Check paid subscriptions first, then admin override via profiles.tier
  -- Exclude auto-created 'free' subscriptions so admin overrides work
  select coalesce(
    (select s.tier from public.subscriptions s
     where s.user_id = v_user_id and s.status = 'active'
       and s.tier != 'free'
       and (s.current_period_end is null or s.current_period_end > now())),
    p.tier,
    'free'
  ) into v_tier
  from public.profiles p
  where p.id = v_user_id;

  return jsonb_build_object('tier', coalesce(v_tier, 'free'));
end;
$$ language plpgsql security definer;

-- delete_user_account: cascading delete of all user data
create or replace function public.delete_user_account()
returns jsonb as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  delete from public.usage_snapshots where user_id = v_user_id;
  delete from public.alerts where user_id = v_user_id;
  delete from public.sessions where user_id = v_user_id;
  delete from public.devices where user_id = v_user_id;
  delete from public.provider_quotas where user_id = v_user_id;
  delete from public.pairing_codes where user_id = v_user_id;
  -- Transfer team ownership or delete orphaned teams
  declare
    v_team record;
    v_new_owner uuid;
  begin
    for v_team in select id from public.teams where owner_id = v_user_id loop
      -- Find next admin, then any member to promote
      select tm.user_id into v_new_owner
      from public.team_members tm
      where tm.team_id = v_team.id and tm.user_id != v_user_id
      order by case when tm.role = 'admin' then 0 else 1 end, tm.joined_at asc
      limit 1;

      if v_new_owner is not null then
        update public.teams set owner_id = v_new_owner where id = v_team.id;
        update public.team_members set role = 'owner'
          where team_id = v_team.id and user_id = v_new_owner;
      else
        delete from public.team_invites where team_id = v_team.id;
        delete from public.teams where id = v_team.id;
      end if;
    end loop;
  end;
  delete from public.team_members where user_id = v_user_id;
  delete from public.subscriptions where user_id = v_user_id;
  delete from public.user_settings where user_id = v_user_id;
  delete from public.profiles where id = v_user_id;

  -- Delete from auth.users to comply with GDPR right to erasure
  delete from auth.users where id = v_user_id;

  return jsonb_build_object('status', 'deleted');
end;
$$ language plpgsql security definer;

-- cleanup_expired_data: delete sessions/alerts/snapshots older than retention period
-- Restricted to service_role only (pg_cron or admin). Not callable by regular users.
create or replace function public.cleanup_expired_data()
returns jsonb as $$
declare
  v_user record;
  v_total_sessions integer := 0;
  v_total_alerts integer := 0;
  v_total_snapshots integer := 0;
  v_deleted integer;
begin
  -- Only allow service_role (pg_cron, admin dashboard) — block regular users
  if current_setting('request.jwt.claims', true)::jsonb ->> 'role' != 'service_role' then
    raise exception 'Forbidden: service_role required';
  end if;

  for v_user in
    select us.user_id, us.data_retention_days
    from public.user_settings us
    where us.data_retention_days > 0
  loop
    -- Clean sessions
    delete from public.sessions
    where user_id = v_user.user_id
      and status = 'Ended'
      and last_active_at < now() - (v_user.data_retention_days || ' days')::interval;
    get diagnostics v_deleted = row_count;
    v_total_sessions := v_total_sessions + v_deleted;

    -- Clean resolved alerts
    delete from public.alerts
    where user_id = v_user.user_id
      and is_resolved = true
      and created_at < now() - (v_user.data_retention_days || ' days')::interval;
    get diagnostics v_deleted = row_count;
    v_total_alerts := v_total_alerts + v_deleted;

    -- Clean usage snapshots
    delete from public.usage_snapshots
    where user_id = v_user.user_id
      and recorded_at < now() - (v_user.data_retention_days || ' days')::interval;
    get diagnostics v_deleted = row_count;
    v_total_snapshots := v_total_snapshots + v_deleted;

    -- Clean stale provider quotas (not updated in retention period)
    delete from public.provider_quotas
    where user_id = v_user.user_id
      and updated_at < now() - (v_user.data_retention_days || ' days')::interval;
  end loop;

  return jsonb_build_object(
    'sessions_deleted', v_total_sessions,
    'alerts_deleted', v_total_alerts,
    'snapshots_deleted', v_total_snapshots
  );
end;
$$ language plpgsql security definer;
