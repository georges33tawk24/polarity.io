# Supabase setup

Fifteen minutes, once. Nothing here needs a paid plan.

## 1. Create the project

<https://supabase.com> → New project. Free tier. Pick a region near your players.

## 2. Enable anonymous sign-in

Dashboard → **Authentication → Providers → Anonymous** → enable.

This is what lets cloud save work before a player has an account, which the spec
requires (§16: never block the first session). It also means that when a player
later signs in with Google or Apple, Supabase keeps the same `auth.uid()` — so
their saves carry over instead of being stranded under a throwaway id.

## 3. Run the schema

Dashboard → **SQL Editor → New query** → paste `schema.sql` → Run.

Read the comments before you run it. Row Level Security is the whole security
model here, because the client only ever holds the anon key.

## 4. Point the game at it

    cp supabase.cfg.example supabase.cfg

Fill in **Project URL** and the **anon / publishable** key from
Dashboard → Settings → API.

`supabase.cfg` is gitignored. The anon key is public by design and ships inside
every Supabase client — that is safe *because* of the RLS policies above.

> **Never** put the `service_role` key in the game, this repo, or a chat window.
> It bypasses every policy.

## 5. Check it

    tools/verify.sh

`Backend` logs which provider it selected on boot. With no config it stays on the
local provider and the game is fully playable offline — a misconfigured backend
degrades to offline, never to a crash.

## What is still not covered

- **Receipt validation** needs an Edge Function; the store grant path is
  documented in DECISIONS §12d.
- **Google / Apple sign-in** needs a native plugin for the on-device flow.
  Supabase handles the token exchange, but the plugin is the missing half.
