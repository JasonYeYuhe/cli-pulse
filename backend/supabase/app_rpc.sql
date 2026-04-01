-- ============================================================
-- CLI Pulse — App RPC Functions
-- Called by the iOS/macOS/watchOS app via authenticated user JWT.
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
    'today_sessions', (select count(*) from public.sessions where user_id = v_user_id and last_active_at::date = v_today)
  ) into v_result;

  return v_result;
end;
$$ language plpgsql security definer;

-- provider_summary: returns per-provider usage for the authenticated user
create or replace function public.provider_summary()
returns jsonb as $$
declare
  v_user_id uuid := auth.uid();
  v_today date := current_date;
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
        'total_usage', coalesce(sum(s.total_usage), 0),
        'estimated_cost', coalesce(sum(s.estimated_cost), 0),
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
