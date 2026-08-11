# Load Test Results: Decoupled Claim + Compute Scaling

**Date:** 2026-03-03
**Migration:** `20260303200001_decouple_claim_from_queue.sql`

## Summary

We decoupled `pgmq.send` from `claim_resource_and_queue` so that the
user-facing claim path is a single `UPDATE ... FOR UPDATE SKIP LOCKED`
with no synchronous queue write.  Queue writes are now handled by a
background `sweep_reserved_to_queue` function running via `pg_cron`
every minute.

We then measured the impact locally, across four managed Supabase
compute tiers (Micro, Small, Medium, XL), and with co-located load
generators — all using Grafana Cloud k6.

## Change

**Before:** `claim_resource_and_queue` did `UPDATE` + `pgmq.send` in
one transaction.

**After:** `claim_resource_and_queue` does only the `UPDATE`.  A new
`sweep_reserved_to_queue(batch_limit)` function runs on a cron schedule
and enqueues RESERVED slots that haven't been queued yet (tracked via a
`queued_at` column on `inventory_slots`).

## Local Results (200 VUs, loopback)

| Variant                 | avg   | median | p95   | rps   | iterations |
|-------------------------|-------|--------|-------|-------|------------|
| Before (with pgmq.send) | 117ms | 105ms  | 265ms | 1,113 | 77,974     |
| After (decoupled)       | 51ms  | 10ms   | 241ms | 1,836 | 128,535    |

**Improvement:** median -90%, avg -56%, throughput +65%.

The median dropping from 105ms to 10ms is the clearest signal: most
requests now complete almost instantly because the synchronous
`pgmq.send` is gone.  The p95 improvement is more modest (-9%) because
the tail is dominated by PostgREST overhead and index scan time under
200-VU concurrency.

## Cloud Results: Shielded (claim_resource_and_queue)

Spike scenario, 100 VUs, 70s duration, Grafana Cloud k6 runners →
Supabase managed project in us-east-1.

### Without co-location (default k6 runner placement)

| Tier               | Cores | RAM  | avg       | p95       | p99        | rps     | total       | Result |
|--------------------|-------|------|-----------|-----------|------------|---------|-------------|--------|
| Micro (old impl)   | 2     | 1GB  | 182-282ms | 479-778ms | 774-1303ms | 239-342 | 19610-28032 | mixed  |
| Micro (decoupled)  | 2     | 1GB  | 196ms     | 533ms     | 860ms      | 322     | 26,440      | FAIL   |
| Small (decoupled)  | 2     | 2GB  | 136ms     | 338ms     | 524ms      | 426     | 34,930      | PASS   |
| Medium (decoupled) | 2     | 4GB  | 135ms     | 338ms     | 528ms      | 413     | 35,074      | PASS   |
| XL (decoupled)     | 4     | 16GB | 134ms     | 338ms     | 541ms      | 431     | 35,362      | PASS   |

### With co-location (k6 runners pinned to us-east-1 Ashburn)

| Tier               | Cores | RAM  | avg   | p95   | p99   | rps | total  | Result |
|--------------------|-------|------|-------|-------|-------|-----|--------|--------|
| Micro (decoupled)  | 2     | 1GB  | 136ms | 338ms | —     | 410 | —      | PASS   |

### Grafana Cloud k6 Run IDs

| Run ID  | Test                        | Tier   | Dashboard                                                  |
|---------|-----------------------------|--------|------------------------------------------------------------|
| 6912496 | shielded (old)              | Micro  | https://davidventimiglia.grafana.net/a/k6-app/runs/6912496 |
| 6912881 | shielded (old)              | Micro  | https://davidventimiglia.grafana.net/a/k6-app/runs/6912881 |
| 6913088 | shielded-no-queue           | Micro  | https://davidventimiglia.grafana.net/a/k6-app/runs/6913088 |
| 6913332 | shielded (decoupled)        | Micro  | https://davidventimiglia.grafana.net/a/k6-app/runs/6913332 |
| 6913413 | shielded (decoupled)        | Small  | https://davidventimiglia.grafana.net/a/k6-app/runs/6913413 |
| 6913462 | shielded (decoupled)        | Medium | https://davidventimiglia.grafana.net/a/k6-app/runs/6913462 |
| 6913517 | shielded (decoupled)        | XL     | https://davidventimiglia.grafana.net/a/k6-app/runs/6913517 |
| 6913706 | shielded (co-located)       | Micro  | https://davidventimiglia.grafana.net/a/k6-app/runs/6913706 |
| 6913726 | unshielded (co-located)     | —      | https://davidventimiglia.grafana.net/a/k6-app/runs/6913726 |

## Cloud Results: Unshielded (finalize_transaction on DB2)

For reference, the unshielded test (direct INSERT to DB2 via
`finalize_transaction`) was stable across all runs:

| Tier   | avg  | p95     | p99      | rps     |
|--------|------|---------|----------|---------|
| Micro  | 47ms | 68-70ms | 95-101ms | 808-810 |
| Small  | 48ms | 68ms    | 90ms     | 806     |
| Medium | 48ms | 70ms    | 102ms    | 802     |
| XL     | 34ms | 43ms    | 58ms     | 903     |

DB2 is on a separate managed project and was not scaled during this
experiment.  The slight improvement at XL is likely due to reduced
network variability during that specific run rather than a DB2 change.

## Analysis

### Decoupling pgmq.send works

Locally, removing `pgmq.send` from the hot path cut median latency by
90% and boosted throughput by 65%.  The synchronous queue write was
clearly the dominant cost in `claim_resource_and_queue`.

### The 338ms floor is network latency, not compute

Without co-location, scaling from Micro to Small appeared to improve
p95 from 533ms to 338ms, while Small/Medium/XL all plateaued at 338ms.
This looked like a compute bottleneck at Micro.

Co-locating the k6 runners with the database (both in us-east-1
Ashburn) disproved that hypothesis.  **Micro co-located: p95 = 338ms**
— identical to non-co-located Small, Medium, and XL.  The ~195ms gap
between non-co-located Micro and the other tiers was entirely network
latency from runner placement, not insufficient RAM or CPU.

The 338ms p95 is the true floor at 100 VUs.  It represents the
combined cost of: PostgREST HTTP handling → PostgreSQL `UPDATE ... FOR
UPDATE SKIP LOCKED` → PostgREST response serialization → network
round-trip within the same AWS region.

### Compute scaling has no effect at this workload

All four tiers (Micro through XL) produce identical results when
network latency is controlled:

- p95 locked at ~338ms
- avg locked at ~136ms
- rps locked at ~410–430

Throughput may also be **load-generator-limited**, not database-limited.
At 100 VUs with ~136ms avg response time and ~50ms avg think time, the
theoretical max is ~540 rps — close to the observed ~425 rps.  The
Grafana Cloud k6 free tier caps at 100 VUs, so we cannot determine
whether larger instances would sustain higher throughput under heavier
load.  A test with more VUs (requiring a paid k6 tier or self-hosted
runners) would be needed to separate the database ceiling from the
load-generator ceiling.

### Throughput floor estimate

Since throughput can only stay the same or improve with more VUs, the
measured results give us a conservative lower bound:

- **At 100 VUs (measured):** ~425 rps sustained across Small, Medium,
  and XL.  This is the known floor.
- **At 200 VUs (projected):** if per-request latency stays flat,
  throughput would roughly double to ~850 rps.  If latency degrades
  under heavier load, the result falls somewhere between 425 and 850.
- **Local reference (200 VUs, loopback):** the decoupled claim
  sustained 1,836 rps, confirming the function itself is not the
  bottleneck at 2x the VU count.

The 425 rps floor holds for every tier including Micro, as long as
clients are co-located in the same region as the database.

### Recommendation

**Micro** is sufficient for this workload at 100 VUs — provided
clients are in the same region as the database.  The co-location test
proved that the apparent Micro→Small improvement was a network latency
artifact, not a compute limitation.

Scaling beyond Micro provides no latency or throughput benefit at this
concurrency level.  Whether larger tiers unlock higher throughput under
heavier load remains an open question — answering it requires more than
100 concurrent VUs, which exceeds the Grafana Cloud k6 free tier.

The most impactful optimization is **co-locating clients with the
database**, not scaling compute.  Ensuring load generators (or
application servers) are in the same AWS region as the Supabase project
eliminated ~195ms of p95 latency — far more than any compute tier
upgrade.

---

## Throughput Ceiling: Stepped VU Ramp

**Date:** 2026-03-03
**Instance:** XL (4-core ARM, 16GB RAM)
**Test:** `throughput-ceiling.js` — stepped ramp 100→200→500→1000→2000
VUs, 60s hold per step, no think time, co-located k6 runners in
us-east-1 Ashburn.  1M inventory slots.

The previous tests at 100 VUs showed ~425 rps with think time, leaving
open whether that was the database ceiling or just a load-generator
limit.  This test removes think time and pushes to 2000 VUs to find
the true ceiling.

### Run 1: Auto-configured PostgREST pool (run 6915240)

| VUs  | avg rps | p95      | errors | Notes                   |
|------|---------|----------|--------|-------------------------|
| 100  | 973     | 156ms    | 0%     | Baseline — fast, clean  |
| 200  | 847     | 446ms    | 0%     | Throughput drops         |
| 500  | 906     | 887ms    | 0%     | No gain over 100 VUs    |
| 1000 | 902     | 1,618ms  | 0%     | Same throughput, 10x p95 |
| 2000 | 777     | 3,704ms  | 0%     | Throughput degrades      |

**Overall:** 839 avg rps, 315k total claims, 0% errors.

The throughput ceiling is **~950 rps**, reached at just 100 VUs.
Adding more VUs increases latency without increasing throughput.  The
system degrades gracefully — zero errors at any VU level, just longer
queue times.

### Run 2: PostgREST pool = 150 connections (run 6915337)

To test whether the PostgREST connection pool was the bottleneck, we
manually increased it from the auto-configured default to 150.

| VUs  | avg rps | p95       | errors | Notes                    |
|------|---------|-----------|--------|--------------------------|
| 100  | 551     | 455ms     | —      | 43% slower than auto     |
| 200  | 322     | 1,829ms   | —      | Catastrophic degradation |
| 500  | 250     | 6,020ms   | —      | Throughput collapses     |
| 1000 | 179     | 15,892ms  | —      | Near-unusable            |
| 2000 | 851     | 13,392ms  | —      | Draining queued requests |

**Overall:** 372 avg rps, 147k total claims, 33% errors (request
timeouts at 2000 VUs).

Increasing the pool made performance **dramatically worse** at every
VU level.  150 concurrent Postgres backends overwhelmed the instance —
too many processes competing for CPU and memory.  The auto-configured
pool size was already well-matched to the instance capacity.

### Grafana Cloud k6 Run IDs

| Run ID  | Test                          | Pool    | Dashboard                                                  |
|---------|-------------------------------|---------|------------------------------------------------------------|
| 6915240 | throughput-ceiling (auto pool) | auto    | https://davidventimiglia.grafana.net/a/k6-app/runs/6915240 |
| 6915337 | throughput-ceiling (pool=150)  | 150     | https://davidventimiglia.grafana.net/a/k6-app/runs/6915337 |

### Analysis

#### The ceiling is ~950 rps on XL

With no think time and co-located runners, `claim_resource_and_queue`
sustains ~950 rps at 100 VUs.  This is the true throughput ceiling for
an XL instance (4-core ARM, 16GB) with the auto-configured PostgREST
pool.  Adding VUs beyond 100 provides no additional throughput — only
higher latency.

#### The bottleneck is Postgres backend throughput, not the pool

Increasing the PostgREST pool from auto to 150 halved throughput and
introduced 33% errors.  This rules out the connection pool as the
bottleneck and confirms the limit is the **Postgres instance itself**
— the combined cost of index scans, row updates, and buffer pool
management on 4 ARM cores.

The auto-tuned pool size is optimal: it limits concurrency to what
Postgres can actually handle, preventing the backend saturation we
observed at 150.

#### Graceful degradation under overload

At the auto pool size, the system handled 2000 VUs with **zero
errors** — it just slowed down.  Latency climbed from 156ms p95 (100
VUs) to 3,704ms p95 (2000 VUs), but every request eventually
completed.  This is the correct behavior for a shock absorber: absorb
the burst, never drop requests.

#### Updated throughput numbers

| Scenario                                | rps  | p95     |
|-----------------------------------------|------|---------|
| 100 VUs, with think time (previous)     | ~425 | 338ms   |
| 100 VUs, no think time (this test)      | ~950 | 156ms   |
| 200 VUs, local loopback (reference)     | 1,836 | 241ms  |

The previous 425 rps measurement was indeed load-generator-limited:
think time capped per-VU throughput.  Without think time, the same 100
VUs produce 2.2x the throughput.

### Recommendation

**~950 rps is the production ceiling** for `claim_resource_and_queue`
on an XL Supabase instance via PostgREST.  This is sufficient for most
burst events (a 10,000-seat venue sells out in ~10 seconds at this
rate).

To go higher, the options are:
1. **Horizontal scaling** — multiple DB1 instances behind a load
   balancer, each with its own inventory partition
2. **Direct Postgres connections** — bypass PostgREST and use pgBouncer
   or direct connections to eliminate HTTP overhead
3. **Larger instance** — a 2XL/4XL with more cores may push the
   ceiling proportionally

Do not increase the PostgREST pool size beyond auto — it makes
performance worse, not better.

---

## Sequence-Based Claiming: O(1) Approach

**Date:** 2026-03-04
**Instance:** Micro (2-core ARM, 1GB RAM)
**Migration:** `20260304200001_sequence_based_claims.sql`

### Change

**Before:** `claim_resource_and_queue` uses `UPDATE ... FOR UPDATE SKIP
LOCKED` — O(N) worst-case scan under concurrency, 2 B-tree operations
per claim (partial index maintenance on `idx_available_slots` and
`idx_reserved_unqueued_slots`).

**After:** Each slot gets a sequential position (`seq_pos`).  A Postgres
sequence atomically assigns positions via `nextval`.  The claim function
does a direct index lookup on `(pool_id, seq_pos)` — no scanning, no
SKIP LOCKED.  Both partial indexes are dropped, enabling HOT updates
(zero index maintenance per claim).

### Run 3: Sequence-based claiming, co-located (run 6918628)

**Test:** `throughput-ceiling.js` — stepped ramp 100→200→500→1000→2000
VUs, 60s hold per step, no think time, co-located k6 runners in
us-east-1 Ashburn.  1M inventory slots with pre-assigned sequential
positions.

| VUs  | avg rps | p95      | Notes                        |
|------|---------|----------|------------------------------|
| 100  | 990     | 170ms    | Near-identical to baseline   |
| 200  | 960     | 338ms    | +13% rps vs baseline         |
| 500  | 996     | 720ms    | +10% rps vs baseline         |
| 1000 | 919     | 1,411ms  | Maintains throughput         |
| 2000 | 867     | 2,853ms  | +12% rps, -23% p95 vs baseline |

**Overall:** 907 avg rps, 338k total claims, 0% errors.

### Run 4: Sequence-based claiming, XL, co-located (run 6919309)

**Instance:** XL (4-core ARM, 16GB RAM)
**Test:** Same as Run 3, but on XL for apples-to-apples comparison
with Run 1.

| VUs  | avg rps | p95      | Notes                         |
|------|---------|----------|-------------------------------|
| 100  | 947     | 179ms    | Baseline-level throughput     |
| 200  | 856     | 422ms    | Slight improvement vs Run 1   |
| 500  | 950     | 664ms    | +5% rps, -25% p95 vs Run 1   |
| 1000 | 957     | 1,308ms  | +6% rps, -19% p95 vs Run 1   |
| 2000 | 831     | 2,893ms  | +7% rps, -22% p95 vs Run 1   |

**Overall:** 878 avg rps, 328k total claims, 0% errors.

### Comparison: All Three Runs

| VUs  | Run 1: SKIP LOCKED (XL) | Run 3: Sequence (Micro) | Run 4: Sequence (XL) |
|------|------------------------|------------------------|---------------------|
| 100  | 973 / 156ms            | 990 / 170ms            | 947 / 179ms         |
| 200  | 847 / 446ms            | 960 / 338ms            | 856 / 422ms         |
| 500  | 906 / 887ms            | 996 / 720ms            | 950 / 664ms         |
| 1000 | 902 / 1,618ms          | 919 / 1,411ms          | 957 / 1,308ms       |
| 2000 | 777 / 3,704ms          | 867 / 2,853ms          | 831 / 2,893ms       |
| **Overall** | **839 rps**     | **907 rps**            | **878 rps**         |

### Analysis

#### Sequence-based approach consistently outperforms SKIP LOCKED

Both sequence runs (Micro and XL) outperform the SKIP LOCKED baseline
at every VU level above 100.  The improvement is most pronounced at
high concurrency: at 1000 VUs, the XL sequence run achieves 957 rps
vs. 902 rps for SKIP LOCKED (+6%) with p95 dropping from 1,618ms to
1,308ms (-19%).

#### p95 improves because per-request cost is lower

The sequence approach reduces per-request work: `nextval` (O(1)) +
direct index lookup replaces scanning past locked rows (O(N) worst
case), and HOT updates eliminate B-tree operations.  Each request
holds its Postgres backend for less time, simultaneously reducing
latency and increasing throughput.

#### Micro + sequence matches or beats XL + SKIP LOCKED

The most striking result: a **Micro** (2-core, 1GB, $25/mo) with the
sequence approach achieved 907 avg rps — outperforming an **XL**
(4-core, 16GB, $150/mo) with SKIP LOCKED at 839 avg rps.  The
algorithm change is worth more than a 6x price increase in compute.

#### Scaling from Micro to XL adds modest value with sequences

Comparing Run 3 (Micro) to Run 4 (XL), both with sequences:
- Overall throughput: 907 vs 878 rps (Micro was slightly higher —
  likely run-to-run variance)
- p95 at 1000 VUs: 1,411ms vs 1,308ms (XL is 7% better)
- p95 at 500 VUs: 720ms vs 664ms (XL is 8% better)

The XL shows modestly better tail latency at high concurrency, but
the throughput difference is within noise.  With the sequence approach,
**Micro is sufficient** — compute scaling provides diminishing returns.

#### Zero errors across all configurations

All three runs handle 2000 VUs with zero meaningful errors.  The
sequence approach maintains graceful degradation regardless of
instance size.

### Run 5: CPU investigation (run 6919590)

**Instance:** XL (4-core ARM, 16GB RAM)
**Purpose:** Identify the ~950 rps ceiling bottleneck by monitoring CPU
during a load test.

| VUs  | avg rps | p95      |
|------|---------|----------|
| 100  | 1,020   | 155ms    |
| 200  | 1,026   | 318ms    |
| 500  | 947     | 742ms    |
| 1000 | 930     | 1,427ms  |
| 2000 | 884     | 2,900ms  |

**Overall:** 918 avg rps, 342k total claims, 0% errors.

#### CPU during test: idle

Both the customer-facing Supabase dashboard and the internal Grafana
(which shows the **whole box** — Postgres and PostgREST together)
reported near-zero CPU utilization during the test:

| Metric                    | During test |
|---------------------------|-------------|
| Customer dashboard CPU    | 0.08%       |
| Internal Grafana (full box) | ~0%       |
| User-mode CPU             | ~0%         |
| System-mode CPU           | ~0%         |
| IOWait                    | ~0%         |

The entire instance — Postgres, PostgREST, and all other processes —
was idle while handling 918 rps across 2000 VUs.

#### The ~950 rps ceiling is not on the box

Since neither Postgres nor PostgREST is CPU-bound, memory-bound, or
IO-bound during the test, the throughput ceiling must be upstream of
the instance:

| Layer                  | CPU during test | Bottleneck? |
|------------------------|----------------|-------------|
| Postgres               | ~0%            | No          |
| PostgREST              | ~0%            | No          |
| Whole box              | ~0%            | No          |
| API gateway (upstream) | not visible    | **Likely**  |

The Supabase API gateway (Kong/Envoy) sits in front of every managed
project.  It handles TLS termination, routing, and request proxying.
This shared infrastructure likely has per-project connection limits or
request rate caps that top out around ~950 rps.

#### Implications

1. **Vertical scaling is pointless** for this workload.  The box is
   idle on a Micro — paying for XL buys nothing.
2. **Algorithm optimization is done.**  The sequence-based approach
   reduced per-request DB work to near-zero CPU cost.  There is no
   further database-level optimization to be found.
3. **The path to higher throughput** is bypassing the API gateway:
   direct Postgres connections via pgBouncer, or horizontal scaling
   across multiple Supabase projects behind a custom load balancer.
4. **~950 rps is a platform limit**, not a database or application
   limit.  This is important context for capacity planning: the
   database can handle far more than the gateway allows through.

### Grafana Cloud k6 Run IDs

| Run ID  | Test                           | Approach           | Dashboard                                                  |
|---------|--------------------------------|--------------------|------------------------------------------------------------|
| 6915240 | throughput-ceiling (auto pool)  | SKIP LOCKED (XL)   | https://davidventimiglia.grafana.net/a/k6-app/runs/6915240 |
| 6918628 | throughput-ceiling (auto pool)  | Sequence (Micro)   | https://davidventimiglia.grafana.net/a/k6-app/runs/6918628 |
| 6919309 | throughput-ceiling (auto pool)  | Sequence (XL)      | https://davidventimiglia.grafana.net/a/k6-app/runs/6919309 |
| 6919590 | throughput-ceiling (CPU test)   | Sequence (XL)      | https://davidventimiglia.grafana.net/a/k6-app/runs/6919590 |

---

## Run 6: Shielded vs Unshielded — 500 VU Cloud Spike

**Date:** 2026-03-05
**Instance:** Micro (2-core ARM, 1GB RAM) — both DB1 and DB2
**Test:** `shielded.js` vs `unshielded.js` — spike scenario, 500 VUs,
70s duration (5s ramp → 60s hold → 5s ramp-down), 10ms fixed think
time, Grafana Cloud k6 runners (pay-as-you-go), co-located in
us-east-1 Ashburn.  500k inventory slots on DB1.

This is the first head-to-head comparison of the **shielded** path
(burst → DB1 claim → background bridge → DB2) against the
**unshielded** path (burst → DB2 directly) under identical conditions.

### Results

| Path       | avg   | p95     | p99     | rps | total  | errors |
|------------|-------|---------|---------|-----|--------|--------|
| Shielded   | 566ms | 991ms   | 2,073ms | 691 | 56,626 | 0%     |
| Unshielded | 906ms | 3,408ms | 5,997ms | 440 | 36,084 | 10.7%  |

### Grafana Cloud k6 Run IDs

| Run ID  | Test        | Dashboard                                                  |
|---------|-------------|------------------------------------------------------------|
| 6930457 | shielded    | https://davidventimiglia.grafana.net/a/k6-app/runs/6930457 |
| 6930467 | unshielded  | https://davidventimiglia.grafana.net/a/k6-app/runs/6930467 |

### Analysis

#### DB1 absorbs the burst; DB2 cannot

At 500 VUs, DB1 handled every request with zero errors.  DB2 dropped
10.7% of requests — over 1 in 10 users would have failed to get a
ticket.  This is the core value proposition of the burst-to-queue
architecture: the ephemeral intake engine absorbs load spikes that
would break the permanent ledger.

#### 3.4x p95 gap

Shielded p95 was 991ms vs unshielded p95 of 3,408ms — a 3.4x
difference.  The gap widens further at p99: 2,073ms vs 5,997ms (2.9x).
Under burst conditions, users hitting DB1 get sub-second responses
while users hitting DB2 directly wait 3-6 seconds — if they get a
response at all.

#### 57% more throughput

The shielded path sustained 691 rps vs 440 rps unshielded — 57% higher
throughput.  This translates directly to tickets sold: in 60 seconds
of burst, DB1 processed 56,626 claims while DB2 managed only 36,084
(and 10.7% of those were errors).

#### Both on Micro instances

Both DB1 and DB2 are Micro instances (2-core ARM, 1GB RAM, $25/mo).
The shielded path's advantage comes entirely from the architecture —
the sequence-based `claim_resource_and_queue` function is cheaper per
request than `finalize_transaction`'s full INSERT + conflict handling.
No additional compute spend is required to get the burst-absorption
benefit.

#### Previous runs underestimated the gap

Earlier tests (Runs 1-5) tested DB1 and DB2 independently at lower
concurrency (100 VUs).  At 100 VUs, both paths performed acceptably.
At 500 VUs, the difference becomes dramatic: the permanent database
starts dropping requests while the ephemeral intake engine stays clean.
Burst tolerance is the point of the architecture, and it only becomes
visible under burst conditions.
