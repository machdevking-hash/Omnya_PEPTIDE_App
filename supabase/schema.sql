-- Omnya database schema for Supabase.
--
-- Run the whole file in the Supabase SQL editor. It is safe to run more than once.
-- It drops and recreates the app tables, so every row in them is deleted. That is
-- intended while the app is pre-launch. After launch, change the schema with
-- additive migrations instead of re-running this file.
--
-- Access model: every install signs in anonymously, so each device has its own
-- auth.uid(). Row level security scopes every row to that user. Circle members
-- see each other's names and dose consistency only, never weights or notes.
-- Photos never leave the device, so there is no photo table.

begin;

drop table if exists public.circle_members, public.circles, public.check_ins,
  public.dose_logs, public.compounds, public.profiles cascade;
drop function if exists public.is_circle_member(text, text);
drop schema if exists app_private cascade;

-- Tables ---------------------------------------------------------------------

create table public.profiles (
  id uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  goals text[] not null default '{}',
  selected_compounds text[] not null default '{}',
  experience_level text,
  cycle_status text,
  day_90_goal text,
  photo_tracking_type text,
  sunday_photo_prompt boolean not null default true,
  protein_target_g smallint check (protein_target_g between 20 and 400),
  updated_at timestamptz not null default now()
);

-- Ids are generated on the device, so they only need to be unique per user.
create table public.compounds (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id text not null,
  name text not null,
  nickname text,
  category text not null check (category in ('body', 'glowAndSkin', 'healAndRecover')),
  dose numeric(10, 3) not null default 0 check (dose >= 0),
  unit text not null default 'mg' check (unit in ('mg', 'mcg', 'IU')),
  route text not null default 'Subcutaneous'
    check (route in ('Subcutaneous', 'Intramuscular', 'Oral', 'Nasal', 'Topical')),
  half_life_hours numeric(8, 2) check (half_life_hours > 0),
  titration jsonb not null default '[]' check (jsonb_typeof(titration) = 'array'),
  mixed_on date,
  vial_days smallint check (vial_days between 1 and 365),
  frequency_days smallint not null default 0 check (frequency_days between 0 and 90),
  next_site text,
  doses_left smallint check (doses_left >= 0),
  cost_per_dose numeric(10, 2) check (cost_per_dose >= 0),
  vial_mg numeric(10, 3) check (vial_mg > 0),
  bac_water_ml numeric(10, 3) check (bac_water_ml > 0),
  start_date date not null default current_date,
  updated_at timestamptz not null default now(),
  primary key (user_id, id)
);

create table public.dose_logs (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id text not null,
  compound_id text not null,
  compound_name text not null,
  dose numeric(10, 3) not null check (dose >= 0),
  unit text not null default 'mg' check (unit in ('mg', 'mcg', 'IU')),
  injection_site text,
  logged_at timestamptz not null,
  primary key (user_id, id)
);

create table public.check_ins (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  id text not null,
  checked_at timestamptz not null,
  energy smallint check (energy between 1 and 5),
  appetite smallint check (appetite between 1 and 5),
  weight_lbs numeric(5, 1) check (weight_lbs between 50 and 800),
  waist_in numeric(4, 1) check (waist_in between 15 and 80),
  sleep_hours numeric(3, 1) check (sleep_hours between 0 and 24),
  pain smallint check (pain between 0 and 10),
  side_effects text[] not null default '{}',
  protein_g smallint check (protein_g between 0 and 600),
  strength smallint check (strength between 1 and 5),
  notes text not null default '' check (char_length(notes) <= 500),
  period_started boolean not null default false,
  primary key (user_id, id)
);

-- A circle's id is its invite code (no 0/O/1/I), so joining never needs a lookup
-- that a non-member could use to list other circles.
create table public.circles (
  id text primary key check (id ~ '^[A-HJ-NP-Z2-9]{5}$'),
  name text not null check (char_length(name) between 1 and 40),
  owner_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  max_members smallint not null default 5 check (max_members between 2 and 5),
  created_at timestamptz not null default now()
);
create index circles_owner_id_idx on public.circles (owner_id);

create table public.circle_members (
  circle_id text not null references public.circles (id) on delete cascade,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 24),
  last_logged_at timestamptz,
  week_start date,
  doses_this_week smallint not null default 0 check (doses_this_week >= 0),
  doses_planned_this_week smallint not null default 0 check (doses_planned_this_week >= 0),
  joined_at timestamptz not null default now(),
  primary key (circle_id, user_id),
  unique (user_id) -- one circle per person
);

-- Row level security ---------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.compounds enable row level security;
alter table public.dose_logs enable row level security;
alter table public.check_ins enable row level security;
alter table public.circles enable row level security;
alter table public.circle_members enable row level security;

create policy "Own profile" on public.profiles for all to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy "Own compounds" on public.compounds for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy "Own dose logs" on public.dose_logs for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy "Own check-ins" on public.check_ins for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- Helpers live in a schema the API does not expose, so they can't be called
-- over REST. Policies still need execute rights on them.
create schema app_private;
revoke all on schema app_private from public;
grant usage on schema app_private to authenticated;

create function app_private.is_circle_member(target_circle text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.circle_members
    where circle_id = target_circle and user_id = (select auth.uid())
  );
$$;

-- True when the circle has a free seat. Also true for a code that doesn't exist,
-- so that insert fails on the foreign key and the app can tell "no such code"
-- apart from "circle is full".
-- ponytail: two people taking the last seat at the same instant can make a 6th
-- member; add a locking trigger if that ever matters.
create function app_private.circle_has_room(target_circle text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select coalesce(
    (select count(m.user_id) < c.max_members
       from public.circles c
       left join public.circle_members m on m.circle_id = c.id
      where c.id = target_circle
      group by c.max_members),
    true
  );
$$;

revoke all on function app_private.is_circle_member(text) from public;
revoke all on function app_private.circle_has_room(text) from public;
grant execute on function app_private.is_circle_member(text) to authenticated;
grant execute on function app_private.circle_has_room(text) to authenticated;

create policy "Owner and members read circle" on public.circles for select to authenticated
  using (owner_id = (select auth.uid()) or app_private.is_circle_member(id));

create policy "Create own circle" on public.circles for insert to authenticated
  with check (owner_id = (select auth.uid()));

create policy "Members read their circle" on public.circle_members for select to authenticated
  using (app_private.is_circle_member(circle_id));

create policy "Join a circle with room" on public.circle_members for insert to authenticated
  with check (user_id = (select auth.uid()) and app_private.circle_has_room(circle_id));

create policy "Update own membership" on public.circle_members for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy "Leave a circle" on public.circle_members for delete to authenticated
  using (user_id = (select auth.uid()));

commit;
