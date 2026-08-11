# SupaTickets

A ticket marketplace for concerts, theater, and sports, built entirely on Supabase. No custom backend server: Postgres, Row Level Security, and a handful of RPC functions do all the work behind a Next.js front end.

This is a demo project for a short conference talk on how little code it takes to build a real web application on Supabase.

## What it demonstrates

| Feature                       | Where                                                                |
|-------------------------------|----------------------------------------------------------------------|
| Auth (email/password)         | `back-end/supabase` auth config, `front-end/src/app/auth/login`      |
| Postgres schema + RLS         | `back-end/supabase/migrations/20260304200000_marketplace_schema.sql` |
| Concurrency-safe reservations | `claim_tickets` / `unclaim_tickets` (`FOR UPDATE SKIP LOCKED`)       |
| Scheduled jobs (pg_cron)      | `reap_expired_reservations`, run every minute                        |
| pgTAP tests                   | `back-end/supabase/tests`                                            |
| Server + client components    | `front-end/src/app`, `front-end/src/components`                      |

Browse events, add tickets to a cart, watch the reservation countdown, check out, and see the order land in your account, all backed by a single Supabase project.

## Repo layout

| Path         | Description                                                         |
|--------------|---------------------------------------------------------------------|
| `back-end/`  | Supabase project: schema, RPC functions, cron job, seed data, tests |
| `front-end/` | Next.js + Tailwind ticketing UI                                     |

## Quickstart

```bash
# 1. Start the local Supabase stack and load the schema + seed data
cd back-end
supabase start
supabase db reset

# 2. Configure and run the front end
cd ../front-end
cp .env.local.example .env.local
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

## Tech stack

Supabase (Postgres, Auth, Realtime, pg_cron) &middot; Next.js &middot; Tailwind CSS
