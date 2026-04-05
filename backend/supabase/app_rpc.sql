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

-- evaluate_budget_alerts: check project costs against budget thresholds
-- Creates alerts for projects exceeding budget, with suppression to prevent spam.
create or replace function public.evaluate_budget_alerts()
returns jsonb as $$
declare
  v_user_id uuid := auth.uid();
  v_threshold numeric;
  v_cooldown integer;
  v_week_start date := current_date - interval '7 days';
  v_project record;
  v_alert_count integer := 0;
  v_suppression_key text;
  v_week_label text := to_char(current_date, 'IYYY-IW');
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  -- Load user thresholds
  select us.project_budget_threshold_usd, us.alert_cooldown_minutes
  into v_threshold, v_cooldown
  from public.user_settings us
  where us.user_id = v_user_id;

  if v_threshold is null or v_threshold <= 0 then
    return jsonb_build_object('alerts_created', 0);
  end if;

  -- Check per-project weekly cost against threshold
  for v_project in
    select
      s.project,
      coalesce(sum(s.estimated_cost), 0) as week_cost,
      max(s.provider) as top_provider
    from public.sessions s
    where s.user_id = v_user_id
      and s.last_active_at >= v_week_start
      and s.project != ''
    group by s.project
    having coalesce(sum(s.estimated_cost), 0) > v_threshold
  loop
    v_suppression_key := 'budget:' || v_user_id || ':' || v_project.project || ':' || v_week_label;

    -- Skip if already alerted this week (strict existence — no cooldown for budget alerts)
    if not exists (
      select 1 from public.alerts
      where user_id = v_user_id and suppression_key = v_suppression_key
    ) then
      insert into public.alerts (id, user_id, type, severity, title, message,
        related_project_name, related_provider, suppression_key, grouping_key)
      values (
        gen_random_uuid()::text, v_user_id,
        'Project Budget Exceeded', 'Warning',
        'Budget exceeded: ' || v_project.project,
        'Project "' || v_project.project || '" has accumulated $' ||
          round(v_project.week_cost::numeric, 2) || ' this week (threshold: $' ||
          round(v_threshold::numeric, 2) || ')',
        v_project.project, v_project.top_provider,
        v_suppression_key, 'budget:' || v_project.project
      );
      v_alert_count := v_alert_count + 1;
    end if;
  end loop;

  -- Cost spike detection: today's total cost > 2x yesterday's
  declare
    v_today_cost numeric;
    v_yesterday_cost numeric;
    v_spike_key text := 'costspike:' || v_user_id || ':' || current_date;
  begin
    select coalesce(sum(estimated_cost), 0) into v_today_cost
    from public.sessions
    where user_id = v_user_id
      and last_active_at >= current_date and last_active_at < current_date + interval '1 day';

    select coalesce(sum(estimated_cost), 0) into v_yesterday_cost
    from public.sessions
    where user_id = v_user_id
      and last_active_at >= current_date - interval '1 day'
      and last_active_at < current_date;

    -- Require minimum $1 yesterday to avoid trivial false positives
    if v_yesterday_cost >= 1.0 and v_today_cost > v_yesterday_cost * 2 then
      if not exists (
        select 1 from public.alerts
        where user_id = v_user_id and suppression_key = v_spike_key
      ) then
        insert into public.alerts (id, user_id, type, severity, title, message,
          suppression_key, grouping_key)
        values (
          gen_random_uuid()::text, v_user_id,
          'Cost Spike', 'Warning',
          'Unusual cost spike detected',
          'Today''s cost ($' || round(v_today_cost::numeric, 2) ||
            ') is more than 2x yesterday ($' || round(v_yesterday_cost::numeric, 2) || ')',
          v_spike_key, 'costspike:daily'
        );
        v_alert_count := v_alert_count + 1;
      end if;
    end if;
  end;

  return jsonb_build_object('alerts_created', v_alert_count);
end;
$$ language plpgsql security definer;

-- ============================================================
-- Team Management RPCs
-- ============================================================

-- create_team: create a new team with the caller as owner
create or replace function public.create_team(p_name text)
returns jsonb as $$
declare
  v_user_id uuid := auth.uid();
  v_team_id uuid;
  v_tier text;
begin
  if v_user_id is null then raise exception 'Not authenticated'; end if;

  if trim(p_name) = '' then raise exception 'Team name cannot be empty'; end if;

  -- Require Pro or Team subscription
  select coalesce(
    (select s.tier from public.subscriptions s
     where s.user_id = v_user_id and s.status = 'active' and s.tier != 'free'),
    (select p.tier from public.profiles p where p.id = v_user_id),
    'free'
  ) into v_tier;
  if v_tier = 'free' then raise exception 'Team features require Pro or Team subscription'; end if;

  insert into public.teams (name, owner_id) values (left(p_name, 100), v_user_id)
  returning id into v_team_id;

  insert into public.team_members (team_id, user_id, role) values (v_team_id, v_user_id, 'owner');

  return jsonb_build_object('team_id', v_team_id, 'name', p_name);
end;
$$ language plpgsql security definer;

-- team_details: return team info + members + invites
create or replace function public.team_details(p_team_id uuid)
returns jsonb as $$
declare
  v_user_id uuid := auth.uid();
  v_team jsonb;
  v_members jsonb;
  v_invites jsonb;
begin
  if v_user_id is null then raise exception 'Not authenticated'; end if;

  -- Verify caller is a member
  if not exists (select 1 from public.team_members where team_id = p_team_id and user_id = v_user_id) then
    raise exception 'Not a member of this team';
  end if;

  select jsonb_build_object('id', t.id, 'name', t.name, 'owner_id', t.owner_id, 'created_at', t.created_at)
  into v_team from public.teams t where t.id = p_team_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'user_id', tm.user_id, 'name', p.name, 'email', p.email,
    'role', tm.role, 'joined_at', tm.joined_at
  )), '[]'::jsonb)
  into v_members
  from public.team_members tm
  join public.profiles p on p.id = tm.user_id
  where tm.team_id = p_team_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', ti.id, 'email', ti.email, 'role', ti.role,
    'created_at', ti.created_at, 'expires_at', ti.expires_at
  )), '[]'::jsonb)
  into v_invites
  from public.team_invites ti
  where ti.team_id = p_team_id and ti.expires_at > now();

  return jsonb_build_object('team', v_team, 'members', v_members, 'invites', v_invites);
end;
$$ language plpgsql security definer;

-- invite_member: send an invite to a team
create or replace function public.invite_member(p_team_id uuid, p_email text, p_role text default 'member')
returns jsonb as $$
declare
  v_user_id uuid := auth.uid();
  v_invite_id uuid;
  v_member_count integer;
begin
  if v_user_id is null then raise exception 'Not authenticated'; end if;

  -- Verify caller is owner or admin
  if not exists (
    select 1 from public.team_members
    where team_id = p_team_id and user_id = v_user_id and role in ('owner', 'admin')
  ) then raise exception 'Only owners and admins can invite members'; end if;

  -- Enforce role constraint: can only invite as 'member'
  if p_role not in ('member') then raise exception 'Can only invite as member role'; end if;

  -- Check for existing invite
  if exists (
    select 1 from public.team_invites
    where team_id = p_team_id and email = p_email and expires_at > now()
  ) then raise exception 'Invite already pending for this email'; end if;

  insert into public.team_invites (team_id, email, role)
  values (p_team_id, left(p_email, 255), p_role)
  returning id into v_invite_id;

  return jsonb_build_object('invite_id', v_invite_id, 'email', p_email);
end;
$$ language plpgsql security definer;

-- accept_invite: join a team via invite
create or replace function public.accept_invite(p_invite_id uuid)
returns jsonb as $$
declare
  v_user_id uuid := auth.uid();
  v_user_email text;
  v_invite record;
begin
  if v_user_id is null then raise exception 'Not authenticated'; end if;

  select email into v_user_email from public.profiles where id = v_user_id;

  select * into v_invite from public.team_invites
  where id = p_invite_id and expires_at > now();

  if v_invite is null then raise exception 'Invite not found or expired'; end if;

  -- Verify email matches
  if v_user_email != v_invite.email then
    raise exception 'This invite was sent to a different email address';
  end if;

  -- Already a member?
  if exists (select 1 from public.team_members where team_id = v_invite.team_id and user_id = v_user_id) then
    delete from public.team_invites where id = p_invite_id;
    raise exception 'Already a member of this team';
  end if;

  insert into public.team_members (team_id, user_id, role)
  values (v_invite.team_id, v_user_id, v_invite.role);

  delete from public.team_invites where id = p_invite_id;

  return jsonb_build_object('team_id', v_invite.team_id, 'role', v_invite.role);
end;
$$ language plpgsql security definer;

-- remove_member: remove a member from a team
create or replace function public.remove_member(p_team_id uuid, p_user_id uuid)
returns jsonb as $$
declare
  v_caller_id uuid := auth.uid();
  v_caller_role text;
begin
  if v_caller_id is null then raise exception 'Not authenticated'; end if;

  select role into v_caller_role from public.team_members
  where team_id = p_team_id and user_id = v_caller_id;

  if v_caller_role is null or v_caller_role not in ('owner', 'admin') then
    raise exception 'Only owners and admins can remove members';
  end if;

  -- Cannot remove the owner
  if exists (select 1 from public.teams where id = p_team_id and owner_id = p_user_id) then
    raise exception 'Cannot remove the team owner';
  end if;

  -- Admins can only remove members, not other admins (owner can remove anyone)
  if v_caller_role = 'admin' then
    if exists (select 1 from public.team_members where team_id = p_team_id and user_id = p_user_id and role = 'admin') then
      raise exception 'Only the owner can remove admins';
    end if;
  end if;

  delete from public.team_members where team_id = p_team_id and user_id = p_user_id;

  return jsonb_build_object('removed', p_user_id);
end;
$$ language plpgsql security definer;

-- update_member_role: change a member's role (owner only)
create or replace function public.update_member_role(p_team_id uuid, p_user_id uuid, p_role text)
returns jsonb as $$
declare
  v_caller_id uuid := auth.uid();
begin
  if v_caller_id is null then raise exception 'Not authenticated'; end if;

  -- Only team owner can change roles
  if not exists (select 1 from public.teams where id = p_team_id and owner_id = v_caller_id) then
    raise exception 'Only the team owner can change roles';
  end if;

  if p_role not in ('admin', 'member') then raise exception 'Invalid role'; end if;

  update public.team_members set role = p_role
  where team_id = p_team_id and user_id = p_user_id and user_id != v_caller_id;

  return jsonb_build_object('user_id', p_user_id, 'role', p_role);
end;
$$ language plpgsql security definer;

-- team_usage_summary: aggregated usage for a team
create or replace function public.team_usage_summary(p_team_id uuid)
returns jsonb as $$
declare
  v_user_id uuid := auth.uid();
  v_week_start date := current_date - interval '7 days';
begin
  if v_user_id is null then raise exception 'Not authenticated'; end if;

  if not exists (select 1 from public.team_members where team_id = p_team_id and user_id = v_user_id) then
    raise exception 'Not a member of this team';
  end if;

  return (
    select jsonb_build_object(
      'team_id', p_team_id,
      'member_count', (select count(*) from public.team_members where team_id = p_team_id),
      'total_usage', coalesce(sum(s.total_usage), 0),
      'total_cost', coalesce(sum(s.estimated_cost), 0),
      'provider_breakdown', coalesce((
        select jsonb_agg(jsonb_build_object(
          'provider', sub.provider, 'usage', sub.usage, 'cost', sub.cost
        ))
        from (
          select s2.provider, sum(s2.total_usage) as usage, sum(s2.estimated_cost) as cost
          from public.sessions s2
          where s2.user_id in (select tm.user_id from public.team_members tm where tm.team_id = p_team_id)
            and s2.last_active_at >= v_week_start
          group by s2.provider order by sum(s2.total_usage) desc
        ) sub
      ), '[]'::jsonb)
    )
    from public.sessions s
    where s.user_id in (select tm.user_id from public.team_members tm where tm.team_id = p_team_id)
      and s.last_active_at >= v_week_start
  );
end;
$$ language plpgsql security definer;
