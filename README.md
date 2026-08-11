# SupaTickets

A ticket marketplace for concerts, theater, and sports, built entirely on Supabase. No custom backend server: Postgres, Row Level Security, and a handful of RPC functions do all the work behind a Next.js front end.

This is a demo project for a short conference talk on how little code it takes to build a real web application on Supabase.

## What it demonstrates

| Feature                       | Where                                             |
|--------------------------------|---------------------------------------------------|
| Auth (email/password)         | Dashboard Auth settings, `front-end/src/app/auth/login` |
| Postgres schema + RLS         | `back-end/01-schema.sql`                          |
| Concurrency-safe reservations | `claim_tickets` / `unclaim_tickets` (`FOR UPDATE SKIP LOCKED`), `back-end/02-functions.sql` |
| Scheduled jobs (pg_cron)      | `reap_expired_reservations`, run every minute, `back-end/03-cron.sql` |
| Server + client components    | `front-end/src/app`, `front-end/src/components`   |

Browse events, add tickets to a cart, watch the reservation countdown, check out, and see the order land in your account, all backed by a single Supabase project.

There's no application server and no migration tooling here on purpose: every piece of `back-end/` is meant to be pasted straight into the Supabase Dashboard's SQL Editor and run live.

## Repo layout

| Path         | Description                                                    |
|--------------|------------------------------------------------------------------|
| `back-end/`  | Numbered SQL scripts: schema, functions, cron job, seed data   |
| `front-end/` | Next.js + Tailwind ticketing UI                                |

## Quickstart

1. Create a project at [supabase.com](https://supabase.com) (or open one you already have).
2. In **Authentication &rarr; Sign In / Providers &rarr; Email**, turn off "Confirm email" so sign-up works instantly during the demo.
3. Open the **SQL Editor** and run these four files in order, pasting each one in and hitting Run:
   - `back-end/01-schema.sql`
   - `back-end/02-functions.sql`
   - `back-end/03-cron.sql`
   - `back-end/04-seed.sql`
4. In **Project Settings &rarr; API**, copy the project URL and anon key into the front end:

   ```bash
   cd front-end
   cp .env.local.example .env.local
   # paste NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY into .env.local
   npm install
   npm run dev
   ```

Open [http://localhost:3000](http://localhost:3000).

## Tech stack

Supabase (Postgres, Auth, Realtime, pg_cron) &middot; Next.js &middot; Tailwind CSS
