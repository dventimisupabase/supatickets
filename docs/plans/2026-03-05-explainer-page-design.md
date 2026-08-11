# Explainer Page Design

**Date:** 2026-03-05
**Audience:** Technical decision-makers (CTOs, architects, senior engineers)
**Visual tone:** Bold/vibrant — dark background, electric blue + warm amber accents, large typography
**Format:** Animated scrollytelling, single `index.html`, zero dependencies

## Sections

### 1. Hero / What
- Full-viewport dark panel, gradient headline: "Burst-to-Queue Ledger"
- Subtitle: "A two-database architecture that absorbs traffic spikes your production database can't."
- Ambient SVG animation: burst of dots → shield (DB1) → orderly trickle → ledger (DB2)
- Scroll-down indicator

### 2. Why / The Problem
- Animated SVG: single DB overwhelmed by spike, error counter climbs to 10.7%
- Headline: "Production databases weren't built for flash mobs."
- 3-4 sentence copy explaining the concurrency problem
- Anchoring stat: "At 500 concurrent users, a direct database takes 3.4s p95 and drops 1 in 10 requests."

### 3. How / Architecture (centerpiece)
Step-by-step SVG diagram builds on scroll through 4 sub-stages:
1. **Claim** — DB1, O(1) sequence UPDATE on UNLOGGED table, ~10ms median
2. **Sweep** — pg_cron batches reserved slots into pgmq every minute
3. **Bridge** — Deno Edge Function drains queue → DB2, idempotent, retry-safe, DLQ
4. **Ledger** — DB2 receives metered stream, never sees the burst

Each step highlights while previous steps dim. Cumulative diagram stays visible.

### 4. Results / Proof
Three animated comparison panels:
1. **Shielded vs Unshielded (500 VUs):** side-by-side bars — 691 vs 440 rps, 991ms vs 3,408ms p95, 0% vs 10.7% errors
2. **Optimization Journey:** coupled (1,113 rps/105ms) → decoupled (1,836 rps/10ms) → sequence (950 rps ceiling, ~0% CPU)
3. **The Punchline:** Micro $25/mo + sequence = 907 rps beats XL $150/mo + SKIP LOCKED = 839 rps

### 5. Footer / CTA
GitHub repo link, demo app link, tech stack badges (Supabase, PostgreSQL, pgmq, Next.js, k6).

## Technical Implementation
- Single `index.html`, zero external dependencies
- Color palette via CSS custom properties: navy background, electric blue (DB1/shielded), warm amber (DB2/unshielded), white text
- `IntersectionObserver` for scroll-triggered animations
- `requestAnimationFrame` for SVG particle/counter animations
- Inline SVG for architecture diagram and bar charts
- CSS transitions/transforms preferred; JS only for sequencing and data-driven elements
- Responsive down to mobile
