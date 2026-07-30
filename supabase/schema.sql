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
