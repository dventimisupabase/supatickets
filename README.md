# Burst-to-Queue Ledger

A two-database architecture that absorbs traffic spikes your production database can't. Built on PostgreSQL and Supabase, it turns a flood of concurrent writes into a metered stream — zero errors, sub-second latency, on the cheapest hardware.

[**Explainer**](https://demo-liart-three-47.vercel.app/about/) | [**Live Demo**](https://demo-liart-three-47.vercel.app/) | [**Benchmarks**](load-test-results.md)

## Why

When 10,000 fans hit "Buy" at the same moment, a conventional database chokes. At **500 concurrent users**, a direct PostgreSQL database takes **3.4s p95** and drops **1 in 10 requests**.

The Burst-to-Queue Ledger eliminates this entirely: **691 rps, 991ms p95, 0% errors** under the same load. And the punchline — a **$25/mo Micro** instance with sequence-based claims (907 rps) outperforms a **$150/mo XL** with SKIP LOCKED (839 rps). Algorithm beats hardware.

## How

| Step | What happens |
|------|-------------|
| **1. Claim** | Users hit DB1 — an O(1) sequence-based UPDATE on an UNLOGGED table. ~10ms median. |
| **2. Sweep** | pg_cron batches reserved slots into a pgmq message queue every minute. |
| **3. Bridge** | A Deno Edge Function drains the queue and commits to DB2. Idempotent, retry-safe, with a dead-letter queue. |
| **4. Ledger** | Confirmed tickets land in the permanent ledger at a metered rate. DB2 never sees the burst. |

## What's in this repo

| Path | Description |
|------|-------------|
| `db1/supabase/` | **DB1 — Intake Engine.** UNLOGGED inventory slots, pgmq, pg_cron sweep, claim RPCs. |
| `db2/supabase/` | **DB2 — Permanent Ledger.** Confirmed tickets table, RLS, idempotent `finalize_transaction`. |
| `db1/supabase/functions/bridge-worker/` | **Bridge Worker.** Deno Edge Function connecting DB1 → DB2. |
| `demo/` | **Demo App.** Next.js + Supabase + Tailwind ticketing UI. |
| `index.html` | **Explainer Page.** Animated scrollytelling, zero dependencies. |
| `tests/load/` | **Load Tests.** k6 suite — shielded vs unshielded, local and cloud. |

## Tech stack

Supabase · PostgreSQL · pgmq · pg_cron · Deno Edge Functions · Next.js · Tailwind · k6
