-- Originalia leads: painted-door answers + progressive request form.
-- Run in Supabase Dashboard > SQL Editor. Safe to re-run (idempotent).
--
-- Security model: the site is static, so the anon key ships in the page. The table
-- has RLS on and NO policies, so anon can't read, insert, update, or delete rows
-- directly. The only thing anon can do is call save_lead(), which validates input
-- and upserts by a client-generated random UUID. Read your leads in the dashboard
-- (Table Editor) or with the service role key; never put that key in the site.

create table if not exists public.leads (
  id              uuid primary key,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  use_case        text,
  email           text,
  first_name      text,
  last_name       text,
  org             text,
  description     text,
  timeline        text,
  landing_source  text,
  step_reached    int  not null default 0,
  completed       boolean not null default false
);

alter table public.leads add column if not exists filters text[];

alter table public.leads enable row level security;

create or replace function public.save_lead(p_id uuid, p_data jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_use_case text := nullif(p_data->>'use_case', '');
  v_timeline text := nullif(p_data->>'timeline', '');
  v_email    text := nullif(left(p_data->>'email', 254), '');
  v_filters  text[] := case when jsonb_typeof(p_data->'filters') = 'array'
    then array(select left(x, 50) from jsonb_array_elements_text(p_data->'filters') x limit 20)
    else null end;
begin
  if p_id is null then
    raise exception 'id required';
  end if;
  if v_use_case is not null and v_use_case not in
     ('tv-film','social','publishing','brand','game','ai-training','other') then
    raise exception 'invalid use_case';
  end if;
  if v_timeline is not null and v_timeline not in
     ('asap','1-3mo','3-6mo','exploring') then
    raise exception 'invalid timeline';
  end if;
  if v_email is not null and v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'invalid email';
  end if;

  insert into public.leads as l
    (id, use_case, email, first_name, last_name, org, description, timeline, filters,
     landing_source, step_reached, completed)
  values (
    p_id,
    v_use_case,
    v_email,
    nullif(left(p_data->>'first_name', 100), ''),
    nullif(left(p_data->>'last_name', 100), ''),
    nullif(left(p_data->>'org', 200), ''),
    nullif(left(p_data->>'description', 4000), ''),
    v_timeline,
    nullif(v_filters, '{}'),
    nullif(left(p_data->>'landing_source', 100), ''),
    coalesce((p_data->>'step_reached')::int, 0),
    coalesce((p_data->>'completed')::boolean, false)
  )
  on conflict (id) do update set
    updated_at     = now(),
    use_case       = coalesce(excluded.use_case, l.use_case),
    email          = coalesce(excluded.email, l.email),
    first_name     = coalesce(excluded.first_name, l.first_name),
    last_name      = coalesce(excluded.last_name, l.last_name),
    org            = coalesce(excluded.org, l.org),
    description    = coalesce(excluded.description, l.description),
    timeline       = coalesce(excluded.timeline, l.timeline),
    filters        = coalesce(excluded.filters, l.filters),
    landing_source = coalesce(l.landing_source, excluded.landing_source),
    step_reached   = greatest(l.step_reached, excluded.step_reached),
    completed      = l.completed or excluded.completed;
end;
$$;

revoke all on function public.save_lead(uuid, jsonb) from public;
grant execute on function public.save_lead(uuid, jsonb) to anon;
