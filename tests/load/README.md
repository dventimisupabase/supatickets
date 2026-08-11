# Load Tests

Validates the central value proposition: **DB2 shielded by DB1 survives burst load that destroys DB2 unshielded.**

## Prerequisites

- Both Supabase instances running: `cd db1 && supabase start` and `cd db2 && supabase start`
- k6 installed: `brew install k6`
- Deno installed: `brew install deno`

## Quick start

```bash
# Run spike scenario (default): shielded then unshielded, back to back
./tests/load/run.sh spike

# Or run ramp / sustained
./tests/load/run.sh ramp
./tests/load/run.sh sustained
```

Results land in `tests/load/results/`.

## With metrics poller (recommended for shielded run)

Open two terminals:

**Terminal 1 — metrics poller:**
```bash
deno run --allow-net --allow-env tests/load/metrics-poller.ts \
  > tests/load/results/metrics-$(date +%s).csv
```

**Terminal 2 — k6:**
```bash
psql "postgresql://postgres:postgres@127.0.0.1:54342/postgres" \
  -f tests/load/setup.sql
k6 run -e SCENARIO=spike \
  --out json=tests/load/results/shielded-spike.json \
  tests/load/shielded.js
```

The CSV from the metrics poller shows `db1_queue_depth` spiking during the burst and `db2_confirmed_total` growing steadily afterward — the visual proof of burst absorption.

## Scenario reference

| Scenario | Pattern | Duration | Local peak VUs | Cloud peak VUs |
|----------|---------|----------|----------------|----------------|
| `spike` | 0 → peak VUs instantly, hold | ~70s | 200 | 100 |
| `ramp` | Step up to peak VUs | ~150s | 200 | 100 |
| `sustained` | Flat VUs | 3m | 100 | 75 |

> **Local VU limits** are set by the PostgREST connection ceiling (~200). Cloud VUs are currently capped at 100 by the Grafana Cloud k6 free tier. Increase in your k6 project settings once billing is configured.

## Throughput ceiling test

Finds the maximum rps of `claim_resource_and_queue` on managed Supabase by stepping VUs from 100 to 2000.

**Requires:** Paid Grafana Cloud k6 (>100 VU limit), `.env.cloud` configured.

```bash
./tests/load/run-throughput-ceiling.sh
```

Seeds 1M slots, runs a stepped ramp (100→200→500→1000→2000 VUs, 60s hold per step), tears down. Total duration ~6 minutes.

No think time — each VU fires as fast as the server responds. The saturation point is where rps stops growing with more VUs.

| Step | VUs  | Duration |
|------|------|----------|
| 1    | 100  | 60s hold |
| 2    | 200  | 60s hold |
| 3    | 500  | 60s hold |
| 4    | 1000 | 60s hold |
| 5    | 2000 | 60s hold |

## What to look for

| Metric | Shielded (DB1) | Unshielded (DB2) |
|--------|---------------|-----------------|
| `http_req_duration p95` | Should stay flat under load | Will spike as DB2 saturates |
| `http_req_failed` | Near 0% | May rise as connections queue |
| `sold_out_responses` | 0 (500k pool) | n/a |
| `db1_queue_depth` (poller) | Spikes during burst, drains after | n/a |
| `db2_confirmed_total` (poller) | Grows steadily after burst | Grows erratically during burst |

---

## Running against Grafana Cloud k6 (cloud scale)

### Prerequisites

- Two managed Supabase projects (DB1 and DB2) with migrations applied and bridge-worker deployed
- A [Grafana Cloud](https://grafana.com/products/cloud/) account with k6 access
- `psql` available locally (for setup/teardown SQL)
- k6 CLI: `brew install k6`

### 1. Provision Supabase projects

For each project (DB1, DB2), from their respective directories:

```bash
# Push migrations
supabase db push --project-ref <project-ref>

# Deploy bridge-worker (DB1 only)
supabase functions deploy bridge-worker --project-ref <db1-project-ref>

# Set edge function secrets (DB1 only)
supabase secrets set --project-ref <db1-project-ref> \
  DB2_URL=https://<db2-project-ref>.supabase.co \
  DB2_KEY=<db2-service-role-key>
```

### 2. Get Grafana Cloud k6 API token

1. Log in to [grafana.com](https://grafana.com)
2. Go to **My Account → API Keys**
3. Create a key with role **MetricsPublisher** (type: k6)
4. Copy the token value

### 3. Configure `.env.cloud`

```bash
cp .env.cloud.example .env.cloud
# Edit .env.cloud with your real values
```

Required variables:

| Variable | Where to find it |
|----------|-----------------|
| `DB1_URL` | Supabase dashboard → Project Settings → API → Project URL |
| `DB1_KEY` | Supabase dashboard → Project Settings → API → service_role key |
| `DB2_URL` | Same for DB2 project |
| `DB2_KEY` | Same for DB2 project |
| `K6_CLOUD_TOKEN` | Grafana Cloud API key (step 2 above) |

### 4. Authenticate k6 CLI (one-time)

```bash
k6 cloud login --token <your-grafana-cloud-k6-api-token>
```

### 5. Run cloud tests

```bash
# Default (spike scenario)
./tests/load/run-cloud.sh

# Or choose a scenario
./tests/load/run-cloud.sh ramp
./tests/load/run-cloud.sh sustained
```

The script runs shielded then unshielded back-to-back, with cleanup between runs. Results appear in your [Grafana Cloud k6 dashboard](https://app.k6.io) within seconds of each run completing.

### 6. Optional: metrics poller against cloud

Point the metrics poller at cloud using the Transaction Pooler URLs from `.env.cloud`:

```bash
DB1_POSTGRES_URL="postgresql://postgres.<db1-ref>:<pass>@aws-0-<region>.pooler.supabase.com:6543/postgres" \
DB2_POSTGRES_URL="postgresql://postgres.<db2-ref>:<pass>@aws-0-<region>.pooler.supabase.com:6543/postgres" \
deno run --allow-net --allow-env tests/load/metrics-poller.ts \
  > tests/load/results/cloud-metrics-$(date +%s).csv
```

---

## Manual teardown

```bash
psql "postgresql://postgres:postgres@127.0.0.1:54342/postgres" \
  -f tests/load/teardown.sql
psql "postgresql://postgres:postgres@127.0.0.1:54442/postgres" \
  -c "DELETE FROM confirmed_tickets WHERE pool_id = 'load_test';"
```
