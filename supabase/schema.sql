-- POLARITY — Supabase schema.
-- Run once in the Supabase SQL editor (Dashboard → SQL → New query → Run).
--
-- Everything here assumes the client holds only the ANON key. Row Level Security
-- is therefore the entire security model: the key grants nothing on its own, and
-- every policy is written against auth.uid(). Get these wrong and the anon key
-- becomes a way to read or edit other players' data.

-- ---------------------------------------------------------------- cloud save
create table if not exists public.saves (
  user_id    uuid primary key references auth.users on delete cascade,
  payload    jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.saves enable row level security;

-- A player may read and write exactly one row: their own.
drop policy if exists "own save read"  on public.saves;
drop policy if exists "own save write" on public.saves;
create policy "own save read"  on public.saves for select using (auth.uid() = user_id);
create policy "own save write" on public.saves for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- --------------------------------------------------------------- leaderboard
create table if not exists public.scores (
  user_id    uuid primary key references auth.users on delete cascade,
  name       text not null default 'Player',
  score      integer not null default 0,
  updated_at timestamptz not null default now(),
  -- Sanity bound. The client already clamps, but a client-side clamp is a
  -- suggestion; this one is enforced.
  constraint score_sane check (score >= 0 and score <= 1000000)
);

alter table public.scores enable row level security;

-- Everyone may READ the board. Nobody may write it directly — writes go through
-- submit_score() below, so "keep the best" cannot be bypassed by a raw PATCH.
drop policy if exists "board is public" on public.scores;
create policy "board is public" on public.scores for select using (true);

-- ------------------------------------------------------------------- ranking
create or replace view public.leaderboard as
  select name, score from public.scores order by score desc limit 200;

create or replace view public.leaderboard_weekly as
  select name, score from public.scores
  where updated_at > now() - interval '7 days'
  order by score desc limit 200;

-- --------------------------------------------------------------- submit_score
-- SECURITY DEFINER so it can write a table the caller cannot write directly.
-- Keeps the BEST score rather than the latest: a replayed request, or a client
-- that submits a worse run, can never lower an existing entry.
create or replace function public.submit_score(p_score integer, p_name text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if p_score < 0 or p_score > 1000000 then
    raise exception 'score out of range';
  end if;

  insert into public.scores (user_id, name, score, updated_at)
  values (auth.uid(), left(coalesce(p_name, 'Player'), 16), p_score, now())
  on conflict (user_id) do update
    set score      = greatest(public.scores.score, excluded.score),
        name       = excluded.name,
        updated_at = now();
end;
$$;

revoke all on function public.submit_score(integer, text) from public;
grant execute on function public.submit_score(integer, text) to anon, authenticated;


-- ===========================================================================
-- Friends
-- ===========================================================================
--
-- Two tables and two functions. The functions exist because the alternative is
-- letting a client read the profiles table to resolve a code, and a table that
-- every client can scan is a directory of every player's id — so lookup happens
-- inside SECURITY DEFINER and the table itself stays unreadable.

-- One row per player. `code` is what a player reads out to a friend; it is
-- generated client-side from the install id and claimed here, so it is stable
-- across reinstalls of the same profile and unique across players.
create table if not exists public.profiles (
  user_id    uuid primary key references auth.users on delete cascade,
  name       text not null default 'Player',
  code       text not null unique,
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- A player may read and write their OWN row and nobody else's. Resolving someone
-- else's code goes through add_friend_by_code, which runs as definer.
drop policy if exists profiles_own_select on public.profiles;
create policy profiles_own_select on public.profiles
  for select using (auth.uid() = user_id);

drop policy if exists profiles_own_upsert on public.profiles;
create policy profiles_own_upsert on public.profiles
  for insert with check (auth.uid() = user_id);

drop policy if exists profiles_own_update on public.profiles;
create policy profiles_own_update on public.profiles
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Directed edges. Adding a friend writes BOTH directions, so neither side has to
-- accept: this is a leaderboard-scope feature, not a social graph with requests,
-- and a pending-invite flow nobody ever confirms is a friends list that is always
-- empty.
create table if not exists public.friendships (
  user_id    uuid not null references auth.users on delete cascade,
  friend_id  uuid not null references auth.users on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, friend_id),
  constraint no_self_friend check (user_id <> friend_id)
);

alter table public.friendships enable row level security;

drop policy if exists friendships_own_select on public.friendships;
create policy friendships_own_select on public.friendships
  for select using (auth.uid() = user_id);

drop policy if exists friendships_own_delete on public.friendships;
create policy friendships_own_delete on public.friendships
  for delete using (auth.uid() = user_id);

-- No INSERT policy on purpose: rows are only ever written by add_friend_by_code,
-- which validates the code first. A client that could insert directly could
-- befriend an arbitrary uuid and read that player's score.

create index if not exists friendships_user_idx on public.friendships (user_id);


-- Claims this player's profile row. Called on every sign-in; the code is only
-- taken if it is free, and a collision surfaces rather than silently reassigning
-- somebody else's code.
create or replace function public.claim_profile(p_code text, p_name text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing text;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  if p_code is null or length(p_code) < 4 or length(p_code) > 16 then
    raise exception 'bad code';
  end if;

  select code into v_existing from public.profiles where user_id = auth.uid();
  if v_existing is not null then
    update public.profiles
       set name = left(coalesce(p_name, 'Player'), 16), updated_at = now()
     where user_id = auth.uid();
    return v_existing;
  end if;

  -- Taken by someone else: the caller keeps its old identity rather than
  -- stealing the code, and gets a suffixed one instead.
  if exists (select 1 from public.profiles where code = upper(p_code)) then
    p_code := upper(p_code) || substr(replace(auth.uid()::text, '-', ''), 1, 3);
  end if;

  insert into public.profiles (user_id, name, code)
  values (auth.uid(), left(coalesce(p_name, 'Player'), 16), upper(p_code))
  on conflict (user_id) do update set name = excluded.name, updated_at = now();

  return (select code from public.profiles where user_id = auth.uid());
end;
$$;

revoke all on function public.claim_profile(text, text) from public;
grant execute on function public.claim_profile(text, text) to anon, authenticated;


-- Resolves a code and links both directions. Returns the friend's name so the UI
-- can confirm who was added rather than just saying "ok".
create or replace function public.add_friend_by_code(p_code text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_friend uuid;
  v_name   text;
  v_count  integer;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select user_id, name into v_friend, v_name
    from public.profiles where code = upper(trim(p_code));
  if v_friend is null then
    raise exception 'no such code';
  end if;
  if v_friend = auth.uid() then
    raise exception 'that is your own code';
  end if;

  -- A cap, because this is the one call that writes rows on someone else's
  -- behalf and an unbounded loop against it would grow the table for free.
  select count(*) into v_count from public.friendships where user_id = auth.uid();
  if v_count >= 200 then
    raise exception 'friend limit reached';
  end if;

  insert into public.friendships (user_id, friend_id)
  values (auth.uid(), v_friend), (v_friend, auth.uid())
  on conflict do nothing;

  return v_name;
end;
$$;

revoke all on function public.add_friend_by_code(text) from public;
grant execute on function public.add_friend_by_code(text) to anon, authenticated;


-- The friends leaderboard, including the caller. Definer because it reads other
-- players' scores — but only ones the caller is actually linked to.
create or replace function public.friend_scores()
returns table (name text, score integer)
language sql
security definer
set search_path = public
as $$
  select coalesce(p.name, s.name, 'Player') as name, s.score
    from public.scores s
    left join public.profiles p on p.user_id = s.user_id
   where s.user_id = auth.uid()
      or s.user_id in (select friend_id from public.friendships
                        where user_id = auth.uid())
   order by s.score desc
   limit 50;
$$;

revoke all on function public.friend_scores() from public;
grant execute on function public.friend_scores() to anon, authenticated;
