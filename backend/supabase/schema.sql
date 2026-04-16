-- ============================================================
-- CLI Pulse — Supabase PostgreSQL Schema
-- Migrated from SQLite, with RLS and Supabase Auth integration
-- ============================================================

-- Required extensions
create extension if not exists pgcrypto;

-- ── Profiles (extends Supabase auth.users) ──
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null default '',
  email text not null default '',
  paired boolean not null default false,
  tier text not null default 'free',
  receipt_verified_at timestamptz,
  last_transaction_id text,
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;

create policy "Users can view own profile"
  on public.profiles for select using (auth.uid() = id);
create policy "Users can update own profile"
  on public.profiles for update using (auth.uid() = id);
create policy "Users can insert own profile"
  on public.profiles for insert with check (auth.uid() = id);

-- Auto-create profile on signup
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, name, email)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'name', ''),
    coalesce(new.email, '')
  );
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ── User Settings ──
create table public.user_settings (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  notifications_enabled boolean not null default true,
  push_policy text not null default 'Warnings + Critical',
  digest_notifications_enabled boolean not null default true,
  digest_interval_minutes integer not null default 15,
  usage_spike_threshold integer not null default 500,
  project_budget_threshold_usd numeric(10,2) not null default 0.25,
  session_too_long_threshold_minutes integer not null default 180,
  offline_grace_period_minutes integer not null default 5,
  repeated_failure_threshold integer not null default 3,
  alert_cooldown_minutes integer not null default 30,
  data_retention_days integer not null default 7,
  login_method text not null default 'apple',
  webhook_url text,
  webhook_enabled boolean not null default false,
  webhook_event_filter jsonb default null,
  updated_at timestamptz not null default now()
);
alter table public.user_settings enable row level security;

create policy "Users can manage own settings"
  on public.user_settings for all using (auth.uid() = user_id);

-- Auto-create settings on profile creation
create or replace function public.handle_new_profile()
returns trigger as $$
begin
  insert into public.user_settings (user_id) values (new.id);
  return new;
end;
$$ language plpgsql security definer;

create trigger on_profile_created
  after insert on public.profiles
  for each row execute function public.handle_new_profile();

-- ── Devices ──
create table public.devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  type text not null default 'macOS',
  system text not null default '',
  helper_version text not null default '0.1.0',
  status text not null default 'Offline',
  cpu_usage integer not null default 0,
  memory_usage integer not null default 0,
  helper_secret text,
  push_token text,
  push_platform text,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
alter table public.devices enable row level security;

create policy "Users can view own devices"
  on public.devices for select using (auth.uid() = user_id);
create policy "Users can insert own devices"
  on public.devices for insert with check (auth.uid() = user_id);
create policy "Users can update own devices"
  on public.devices for update using (auth.uid() = user_id);
create policy "Users can delete own devices"
  on public.devices for delete using (auth.uid() = user_id);

-- Revoke direct SELECT on helper_secret from authenticated users;
-- only SECURITY DEFINER RPCs (helper_heartbeat, helper_sync) can read it.
revoke select (helper_secret) on public.devices from authenticated;

create index idx_devices_user_id on public.devices(user_id);
create index idx_devices_user_status on public.devices(user_id, status);
create index idx_devices_push_token on public.devices(user_id) where push_token is not null;

-- ── Pairing Codes ──
create table public.pairing_codes (
  code text primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  failed_attempts integer not null default 0,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '10 minutes')
);
alter table public.pairing_codes enable row level security;

create policy "Users can manage own pairing codes"
  on public.pairing_codes for all using (auth.uid() = user_id);

-- ── Sessions ──
create table public.sessions (
  id text not null check (length(id) <= 128),
  user_id uuid not null references public.profiles(id) on delete cascade,
  device_id uuid references public.devices(id) on delete set null,
  name text not null default '',
  provider text not null,
  project text not null default '',
  status text not null default 'Running',
  total_usage integer not null default 0,
  estimated_cost numeric(10,4),
  requests integer not null default 0,
  error_count integer not null default 0,
  collection_confidence text not null default 'medium',
  started_at timestamptz not null default now(),
  last_active_at timestamptz not null default now(),
  synced_at timestamptz not null default now(),
  primary key (id, user_id),
  constraint chk_sessions_cost_bounds check (estimated_cost is null or (estimated_cost >= 0 and estimated_cost < 10000))
);
alter table public.sessions enable row level security;

create policy "Users can manage own sessions"
  on public.sessions for all using (auth.uid() = user_id);

create index idx_sessions_user_id on public.sessions(user_id);
create index idx_sessions_provider on public.sessions(provider);
create index idx_sessions_started_at on public.sessions(started_at);
create index idx_sessions_status on public.sessions(status);
create index idx_sessions_user_last_active on public.sessions(user_id, last_active_at);
create index idx_sessions_device_id on public.sessions(device_id);

-- ── Alerts ──
create table public.alerts (
  id text not null check (length(id) <= 128),
  user_id uuid not null references public.profiles(id) on delete cascade,
  type text not null,
  severity text not null default 'Info',
  title text not null,
  message text not null default '',
  is_read boolean not null default false,
  is_resolved boolean not null default false,
  acknowledged_at timestamptz,
  snoozed_until timestamptz,
  related_project_id text,
  related_project_name text,
  related_session_id text,
  related_session_name text,
  related_provider text,
  related_device_name text,
  source_kind text,
  source_id text,
  grouping_key text,
  suppression_key text,
  created_at timestamptz not null default now(),
  primary key (id, user_id)
);
alter table public.alerts enable row level security;

create policy "Users can manage own alerts"
  on public.alerts for all using (auth.uid() = user_id);

create index idx_alerts_user_id on public.alerts(user_id);
create index idx_alerts_created_at on public.alerts(created_at);
create index idx_alerts_user_resolved on public.alerts(user_id, is_resolved);
create index idx_alerts_user_suppression_resolved on public.alerts(user_id, suppression_key, is_resolved);

-- ── Subscriptions ──
create table public.subscriptions (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  tier text not null default 'free',
  status text not null default 'active',
  current_period_start timestamptz,
  current_period_end timestamptz,
  trial_end timestamptz,
  cancel_at_period_end boolean not null default false,
  apple_transaction_id text,
  apple_original_transaction_id text,
  apple_product_id text,
  play_order_id text,
  play_purchase_token text,
  platform text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.subscriptions enable row level security;

-- Unique constraints to enforce anti-replay at DB level (prevents concurrent race)
create unique index idx_sub_apple_txn on public.subscriptions(apple_original_transaction_id) where apple_original_transaction_id is not null;
create unique index idx_sub_play_order on public.subscriptions(play_order_id) where play_order_id is not null;
create unique index idx_sub_play_token on public.subscriptions(play_purchase_token) where play_purchase_token is not null;

create policy "Users can view own subscription"
  on public.subscriptions for select using (auth.uid() = user_id);
-- Service role (backend) manages subscriptions via Apple receipt verification.
-- No public write policy — only service_role key can update subscriptions.

-- Auto-create free subscription on profile creation
create or replace function public.handle_new_subscription()
returns trigger as $$
begin
  insert into public.subscriptions (user_id) values (new.id);
  return new;
end;
$$ language plpgsql security definer;

create trigger on_profile_created_subscription
  after insert on public.profiles
  for each row execute function public.handle_new_subscription();

-- ── Teams ──
create table public.teams (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.teams enable row level security;

-- ── Team Members ──
create table public.team_members (
  team_id uuid not null references public.teams(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'member',
  joined_at timestamptz not null default now(),
  primary key (team_id, user_id)
);
alter table public.team_members enable row level security;
create index idx_team_members_user_id on public.team_members(user_id);

-- ── Team Invites ──
create table public.team_invites (
  id uuid primary key default gen_random_uuid(),
  team_id uuid not null references public.teams(id) on delete cascade,
  email text not null,
  role text not null default 'member',
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '7 days')
);
alter table public.team_invites enable row level security;
create index idx_team_invites_team_id on public.team_invites(team_id);
create index idx_team_invites_team_email on public.team_invites(team_id, email);

-- Team RLS policies (after all team tables exist)
create policy "Team members can view team"
  on public.teams for select using (
    id in (select team_id from public.team_members where user_id = auth.uid())
  );
create policy "Owner can manage team"
  on public.teams for all using (auth.uid() = owner_id);

create policy "Team members can view members"
  on public.team_members for select using (
    team_id in (select team_id from public.team_members where user_id = auth.uid())
  );
-- Admins can insert/delete members but only owners can update roles
create policy "Owner/admin can add members (as member role only)"
  on public.team_members for insert with check (
    role = 'member' and team_id in (
      select team_id from public.team_members
      where user_id = auth.uid() and role in ('owner', 'admin')
    )
  );
create policy "Owner/admin can delete members"
  on public.team_members for delete using (
    team_id in (
      select team_id from public.team_members
      where user_id = auth.uid() and role in ('owner', 'admin')
    )
  );
create policy "Only owner can update member roles"
  on public.team_members for update using (
    team_id in (
      select tm.team_id from public.team_members tm
      join public.teams t on t.id = tm.team_id
      where t.owner_id = auth.uid()
    )
  );

create policy "Team owner/admin can manage invites"
  on public.team_invites for all using (
    team_id in (
      select team_id from public.team_members
      where user_id = auth.uid() and role in ('owner', 'admin')
    )
  );

-- ── Usage Snapshots (time-series for trend charts) ──
create table public.usage_snapshots (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  provider text not null,
  usage_value integer not null default 0,
  recorded_at timestamptz not null default now()
);
alter table public.usage_snapshots enable row level security;

create policy "Users can manage own snapshots"
  on public.usage_snapshots for all using (auth.uid() = user_id);

create index idx_usage_snapshots_user_provider on public.usage_snapshots(user_id, provider);
create index idx_usage_snapshots_recorded_at on public.usage_snapshots(recorded_at);

-- ── Provider Quotas (remaining quota per provider) ──
create table public.provider_quotas (
  user_id uuid not null references public.profiles(id) on delete cascade,
  provider text not null,
  remaining integer not null default 0,
  quota integer,
  plan_type text,
  reset_time timestamptz,
  tiers jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (user_id, provider)
);
alter table public.provider_quotas enable row level security;

create policy "Users can manage own quotas"
  on public.provider_quotas for all using (auth.uid() = user_id);

-- ── Views for dashboard aggregations ──

-- Today's usage per provider
create or replace view public.provider_usage_today as
select
  s.user_id,
  s.provider,
  coalesce(sum(s.total_usage), 0) as today_usage,
  count(*) as session_count,
  coalesce(sum(s.estimated_cost), 0) as estimated_cost
from public.sessions s
where s.last_active_at >= current_date and s.last_active_at < current_date + interval '1 day'
group by s.user_id, s.provider;

-- This week's usage per provider
create or replace view public.provider_usage_week as
select
  s.user_id,
  s.provider,
  coalesce(sum(s.total_usage), 0) as week_usage,
  coalesce(sum(s.estimated_cost), 0) as estimated_cost
from public.sessions s
where s.started_at >= (date_trunc('week', current_date) at time zone 'UTC')
group by s.user_id, s.provider;

-- ── Webhook settings index ──
create index idx_user_settings_webhook_enabled
  on public.user_settings(user_id)
  where webhook_enabled = true and webhook_url is not null;

-- ── Daily Usage Metrics (per-day per-model token counts and costs) ──
create table public.daily_usage_metrics (
  user_id uuid not null references public.profiles(id) on delete cascade,
  metric_date date not null,
  provider text not null,
  model text not null,
  input_tokens bigint not null default 0,
  cached_tokens bigint not null default 0,
  output_tokens bigint not null default 0,
  cost numeric(10,6) not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, metric_date, provider, model)
);
alter table public.daily_usage_metrics enable row level security;

create policy "Users own metrics"
  on public.daily_usage_metrics for all using (auth.uid() = user_id);

create index idx_daily_usage_metrics_user_date
  on public.daily_usage_metrics(user_id, metric_date desc);

-- RPC: upsert_daily_usage
-- Batch upsert daily usage metrics from macOS scanner.
create or replace function public.upsert_daily_usage(metrics jsonb)
returns jsonb as $$
declare
  v_user_id uuid := auth.uid();
  v_count int := 0;
  v_item jsonb;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  for v_item in select * from jsonb_array_elements(metrics)
  loop
    insert into public.daily_usage_metrics (
      user_id, metric_date, provider, model,
      input_tokens, cached_tokens, output_tokens, cost, updated_at
    ) values (
      v_user_id,
      (v_item->>'metric_date')::date,
      v_item->>'provider',
      v_item->>'model',
      coalesce((v_item->>'input_tokens')::bigint, 0),
      coalesce((v_item->>'cached_tokens')::bigint, 0),
      coalesce((v_item->>'output_tokens')::bigint, 0),
      coalesce((v_item->>'cost')::numeric, 0),
      now()
    )
    on conflict (user_id, metric_date, provider, model)
    do update set
      input_tokens = excluded.input_tokens,
      cached_tokens = excluded.cached_tokens,
      output_tokens = excluded.output_tokens,
      cost = excluded.cost,
      updated_at = now();
    v_count := v_count + 1;
  end loop;

  return jsonb_build_object('upserted', v_count);
end;
$$ language plpgsql security definer;

-- RPC: get_daily_usage
-- Returns the most recent N days of usage data for the authenticated user.
create or replace function public.get_daily_usage(days int default 30)
returns jsonb as $$
declare
  v_user_id uuid := auth.uid();
  v_since date := current_date - days;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;

  return coalesce(
    (select jsonb_agg(row_to_json(t)) from (
      select metric_date, provider, model,
             input_tokens, cached_tokens, output_tokens, cost
      from public.daily_usage_metrics
      where user_id = v_user_id and metric_date >= v_since
      order by metric_date desc, provider, model
    ) t),
    '[]'::jsonb
  );
end;
$$ language plpgsql security definer;
