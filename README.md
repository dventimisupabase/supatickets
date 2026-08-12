# SupaTickets

A ticket marketplace for concerts, theater, and sports, built entirely on Supabase. No custom backend server: Postgres, Row Level Security, and a handful of RPC functions do all the work behind a Next.js front end.

This is a demo project for a short conference talk on how little code it takes to build a real web application on Supabase.

## What it demonstrates

| Feature                       | Where                                             |
|--------------------------------|---------------------------------------------------|
| Auth (email/password)         | Dashboard Auth settings, `front-end/src/app/login` |
| Postgres schema                | `back-end/01-schema.sql`                          |
| Row Level Security            | `back-end/02-rls.sql`                             |
| Concurrency-safe reservations | `claim_tickets` / `unclaim_tickets` (`FOR UPDATE SKIP LOCKED`), scheduled cleanup via pg_cron, `back-end/03-functions.sql` |
| Indexes                       | `back-end/04-indexes.sql`                         |
| Realtime                      | Live "tickets left" via `postgres_changes`, `front-end/src/components.tsx` |
| Server + client components    | `front-end/src/app`, `front-end/src/components.tsx` |

Browse events, add tickets to a cart, watch the reservation countdown, check out, and see the order land in your account, all backed by a single Supabase project. Open the same event in two tabs and buy in one: the other tab's "tickets left" updates live, no refresh.

There's no application server and no migration tooling here on purpose: every piece of `back-end/` is meant to be pasted straight into the Supabase Dashboard's SQL Editor and run live.

## Repo layout

| Path         | Description                                                    |
|--------------|------------------------------------------------------------------|
| `back-end/`  | Numbered SQL scripts: schema, RLS, functions (+ cron), indexes, seed data |
| `front-end/` | Next.js + Tailwind ticketing UI                                |

## Quickstart

1. Create a project at [supabase.com](https://supabase.com) (or open one you already have). If you generate a database password during setup, copy it somewhere safe, Supabase won't show it to you again. You won't need it for the rest of this Quickstart (the SQL Editor uses your dashboard login, not this password), but you'd need it later for any direct Postgres connection (`psql`, a DB client, the Supabase CLI).
2. In **Authentication &rarr; Sign In / Providers &rarr; Email**, turn off "Confirm email" so sign-up works instantly during the demo.
3. Open the **SQL Editor** and run these five files in order, pasting each one in and hitting Run:
   - `back-end/01-schema.sql`
   - `back-end/02-rls.sql`
   - `back-end/03-functions.sql`
   - `back-end/04-indexes.sql`
   - `back-end/05-seed.sql`
4. In **Project Settings &rarr; API**, copy the project URL and anon key into the front end. Create `front-end/.env.local` with:

   ```
   NEXT_PUBLIC_SUPABASE_URL=<your project URL>
   NEXT_PUBLIC_SUPABASE_ANON_KEY=<your anon key>
   ```

   Then:

   ```bash
   cd front-end
   npm install
   npm run dev
   ```

   Open [http://localhost:3000](http://localhost:3000).

5. To run the talk from a real URL instead of localhost, deploy to Vercel.

   **Prefer clicking to typing?** This button walks through the same setup (project root, env vars) in a web form, no terminal required:

   [![Deploy with Vercel](https://vercel.com/button)](https://vercel.com/new/clone?repository-url=https%3A%2F%2Fgithub.com%2Fdventimisupabase%2Fsupatickets&root-directory=front-end&project-name=supatickets&repository-name=supatickets&env=NEXT_PUBLIC_SUPABASE_URL,NEXT_PUBLIC_SUPABASE_ANON_KEY&envDescription=Copy%20these%20from%20your%20Supabase%20project%27s%20Settings%20-%3E%20API%20page)

   **Prefer the terminal?** Deploy with the Vercel CLI directly from your machine, no GitHub integration, no auto-deploy on push, just you running a command when you want a new build live:

   ```bash
   npx vercel login                                            # one-time browser login
   npx vercel link                                             # create/link a Vercel project
   npx vercel env add NEXT_PUBLIC_SUPABASE_URL production      # paste your Supabase project URL
   npx vercel env add NEXT_PUBLIC_SUPABASE_ANON_KEY production # paste your anon key
   npx vercel --prod                                           # build and deploy, prints the live URL
   ```

   Re-run `npx vercel --prod` any time you want to push a change live.

## Tech stack

Supabase (Postgres, Auth, Realtime, pg_cron) &middot; Next.js &middot; Tailwind CSS
