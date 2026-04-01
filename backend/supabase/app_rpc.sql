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

  select jsonb_build_object(
    'today_usage', coalesce((select sum(total_usage) from public.sessions where user_id = v_user_id and last_active_at::date = v_today), 0),
    'today_cost', coalesce((select sum(estimated_cost) from public.sessions where user_id = v_user_id and last_active_at::date = v_today), 0),
    'active_sessions', (select count(*) from public.sessions where user_id = v_user_id and status = 'Running'),
    'online_devices', (select count(*) from public.devices where user_id = v_user_id and status = 'Online'),
    'unresolved_alerts', (select count(*) from public.alerts where user_id = v_user_id and is_resolved = false),
    'today_sessions', coalesce((select sum(requests) from public.sessions where user_id = v_user_id and last_active_at::date = v_today), 0)
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

  return (
    select coalesce(jsonb_agg(row_data), '[]'::jsonb)
    from (
      select jsonb_build_object(
        'provider', s.provider,
        'today_usage', coalesce(sum(case when s.last_active_at::date = v_today then s.total_usage else 0 end), 0),
        'total_usage', coalesce(sum(case when s.last_active_at::date >= v_week_start then s.total_usage else 0 end), 0),
        'estimated_cost', coalesce(sum(case when s.last_active_at::date >= v_week_start then s.estimated_cost else 0 end), 0),
        'remaining', pq.remaining
      ) as row_data
      from public.sessions s
      left join public.provider_quotas pq on pq.user_id = v_user_id and pq.provider = s.provider
      where s.user_id = v_user_id
      group by s.provider, pq.remaining
      order by sum(s.total_usage) desc
    ) sub
  );
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

  delete from public.alerts where user_id = v_user_id;
  delete from public.sessions where user_id = v_user_id;
  delete from public.devices where user_id = v_user_id;
  delete from public.provider_quotas where user_id = v_user_id;
  delete from public.pairing_codes where user_id = v_user_id;
  delete from public.profiles where id = v_user_id;

  return jsonb_build_object('status', 'deleted');
end;
$$ language plpgsql security definer;
