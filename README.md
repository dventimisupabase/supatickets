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
2. In **Authentication &rarr; Sign In / Providers**, under "User Signups," turn off the **Confirm email** toggle so sign-up works instantly during the demo. Click **Save changes**, it won't take effect otherwise.
3. Open the **SQL Editor** and run these five files in order, pasting each one in and hitting Run:
   - `back-end/01-schema.sql`
   - `back-end/02-rls.sql`
   - `back-end/03-functions.sql`
   - `back-end/04-indexes.sql`
   - `back-end/05-seed.sql`

   Running `01-schema.sql` triggers a "Potential issue detected" popup, since it creates tables without enabling Row Level Security. Click **Run without RLS**, that's expected: `02-rls.sql` is the very next file, and it's the one that turns RLS on.
4. Copy two values from **Project Settings** and keep them handy, you'll need them in the next step:
   - **Data API** (Overview tab): the Project URL
   - **API Keys** (Publishable and secret API keys tab): the **Publishable key** (`sb_publishable_...`), Supabase's replacement for the legacy anon key
5. Deploy to Vercel. There's no Vercel project yet, this step is what creates it.

   **Prefer clicking to typing?** No GitHub account needed for this path:

   1. Download [`front-end.zip`](https://github.com/dventimisupabase/supatickets/releases/download/front-end-latest/front-end.zip), it's just the `front-end/` folder, packaged as a GitHub release asset so anyone can download it without signing in to GitHub.
   2. Go to [vercel.com/drop](https://vercel.com/drop) and drag the zip onto the page. Sign in to Vercel (or create a free account) if you haven't already, give the project a name, and click **Deploy**.
   3. This first build fails, that's expected: it doesn't have the Supabase credentials yet. In the new project's **Settings &rarr; Environment Variables**, add `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` using the values from step 4.
   4. Go to **Deployments**, open the **&bull;&bull;&bull;** menu on the failed deployment, and click **Redeploy**. This time it builds clean.

   **Prefer the terminal?** Deploy with the Vercel CLI directly from your machine, no GitHub integration, no auto-deploy on push, just you running a command when you want a new build live:

   ```bash
   cd front-end
   npx vercel login                                            # one-time browser login
   npx vercel link                                             # create/link a Vercel project
   npx vercel env add NEXT_PUBLIC_SUPABASE_URL production      # paste your Supabase project URL from step 4
   npx vercel env add NEXT_PUBLIC_SUPABASE_ANON_KEY production # paste your publishable key from step 4
   npx vercel --prod                                           # build and deploy, prints the live URL
   ```

   Re-run `npx vercel --prod` any time you want to push a change live.

Vercel prints a live URL once the deploy finishes, that's what you'll use on stage.

The `front-end.zip` release asset isn't rebuilt automatically. After changing anything under `front-end/`, refresh it with:

```bash
git archive --format=zip -o front-end.zip HEAD:front-end
gh release upload front-end-latest front-end.zip --clobber
rm front-end.zip
```

## Tech stack

Supabase (Postgres, Auth, Realtime, pg_cron) &middot; Next.js &middot; Tailwind CSS
