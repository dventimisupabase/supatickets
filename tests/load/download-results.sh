#!/usr/bin/env bash
# tests/load/download-results.sh
# Download test run summaries and metric time-series from Grafana Cloud k6.
#
# Usage:
#   ./tests/load/download-results.sh            # list recent runs
#   ./tests/load/download-results.sh <run_id>   # download a specific run
#   ./tests/load/download-results.sh <id1> <id2> [label1] [label2]  # compare two runs

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$REPO_ROOT/.env.cloud"
RESULTS_DIR="$SCRIPT_DIR/results"
mkdir -p "$RESULTS_DIR"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found."
  exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"
: "${K6_CLOUD_TOKEN:?K6_CLOUD_TOKEN must be set in .env.cloud}"

K6_API="https://api.k6.io"
PROJECT_ID=6883841

api_get() {
  curl -sf --globoff "$K6_API/$1" -H "Authorization: Token $K6_CLOUD_TOKEN"
}

# Fetch time-series for one metric+aggregation, return [[ts, val], ...] as JSON
fetch_metric() {
  local run_id="$1" metric="$2" query="$3"
  local started="$4" ended="$5"
  local url
  url="$K6_API/cloud/v5/test_runs/$run_id/query_range_k6(metric='$metric',query='$query',step=10,start=${started},end=${ended})"
  curl -sf --globoff "$url" -H "Authorization: Token $K6_CLOUD_TOKEN"
}

download_run() {
  local run_id="$1"
  echo "--- Downloading run $run_id ---"

  # Run metadata
  local run_file="$RESULTS_DIR/cloud-run-${run_id}.json"
  api_get "loadtests/v2/runs/$run_id" | python3 -c "
import sys, json
d = json.load(sys.stdin)
run = d['k6-run']
summary = {
  'run_id':        run['id'],
  'test_name':     run.get('test_name', ''),
  'run_status':    run['run_status'],
  'result_status': run['result_status'],
  'started':       run['started'],
  'ended':         run['ended'],
  'duration_sec':  run['duration'],
  'vus':           run['vus'],
  'dashboard_url': run.get('k6_runtime_config', {}).get('testRunDetails', ''),
}
print(json.dumps(summary, indent=2))
" > "$run_file"

  # Read timestamps for metric queries
  local started ended
  started=$(python3 -c "import json; d=json.load(open('$run_file')); print(d['started'])")
  ended=$(python3 -c "import json; d=json.load(open('$run_file')); print(d['ended'])")

  # Fetch metric time-series
  local metrics_file="$RESULTS_DIR/cloud-run-${run_id}-timeseries.json"
  python3 - "$run_id" "$started" "$ended" "$K6_CLOUD_TOKEN" <<'PYEOF' > "$metrics_file"
import sys, json, urllib.request

run_id, started, ended, token = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
BASE = "https://api.k6.io/cloud/v5"

def fetch_range(metric, query):
    """Per-interval time-series (for charting)."""
    url = f"{BASE}/test_runs/{run_id}/query_range_k6(metric='{metric}',query='{query}',step=10,start={started},end={ended})"
    req = urllib.request.Request(url, headers={"Authorization": f"Token {token}"})
    try:
        with urllib.request.urlopen(req) as r:
            d = json.loads(r.read())
        results = d.get("data", {}).get("result", [])
        return results[0].get("values", []) if results else []
    except Exception:
        return []

def fetch_aggregate(metric, query):
    """True aggregate over the full run (matches Grafana dashboard)."""
    url = f"{BASE}/test_runs/{run_id}/query_aggregate_k6(metric='{metric}',query='{query}',start={started},end={ended})"
    req = urllib.request.Request(url, headers={"Authorization": f"Token {token}"})
    try:
        with urllib.request.urlopen(req) as r:
            d = json.loads(r.read())
        results = d.get("data", {}).get("result", [])
        values = results[0].get("values", []) if results else []
        return round(values[0][1], 3) if values else None
    except Exception:
        return None

out = {
    "run_id": run_id,
    "http_req_duration_ms": {
        "p95":         fetch_aggregate("http_req_duration", "p95"),
        "p99":         fetch_aggregate("http_req_duration", "p99"),
        "avg":         fetch_aggregate("http_req_duration", "avg"),
        "p95_series":  fetch_range("http_req_duration", "p95"),
    },
    "http_req_failed_rate": {
        "rate":   fetch_aggregate("http_req_failed", "rate"),
        "series": fetch_range("http_req_failed", "rate"),
    },
    "http_reqs_per_sec": {
        "rps_avg": fetch_aggregate("http_reqs", "rate"),
        "total":   fetch_aggregate("http_reqs", "count"),
        "series":  fetch_range("http_reqs", "rate"),
    },
    "claim_duration_ms": {
        "p95":        fetch_aggregate("claim_duration_ms", "p95"),
        "p99":        fetch_aggregate("claim_duration_ms", "p99"),
        "p95_series": fetch_range("claim_duration_ms", "p95"),
    },
}
print(json.dumps(out, indent=2))
PYEOF

  echo "    Summary    : $run_file"
  echo "    Time-series: $metrics_file"

  # Human-readable summary
  python3 - "$run_file" "$metrics_file" <<'PYEOF'
import json, sys

run = json.load(open(sys.argv[1]))
ts  = json.load(open(sys.argv[2]))

status = "PASSED" if run["result_status"] == 0 else "FAILED (thresholds)"
print(f"    Result     : {status}")
print(f"    Test       : {run['test_name']}  |  VUs: {run['vus']}  |  {run['started']} -> {run['ended']}")
print(f"    URL        : {run['dashboard_url']}")
print()

def v(d, key, unit="ms"):
    val = d.get(key)
    return f"{val:.0f}{unit}" if val is not None else "n/a"

dur = ts["http_req_duration_ms"]
print(f"    http_req_duration     :  avg={v(dur,'avg')}  p95={v(dur,'p95')}  p99={v(dur,'p99')}")
fail = ts["http_req_failed_rate"]
rate = fail.get("rate")
rate_str = f"{rate*100:.3f}%" if rate is not None else "n/a"
print(f"    http_req_failed       :  {rate_str}")
reqs = ts["http_reqs_per_sec"]
print(f"    http_reqs             :  rps={v(reqs,'rps_avg','')}  total={v(reqs,'total','')}")
cl = ts["claim_duration_ms"]
if cl.get("p95"):
    print(f"    claim_duration_ms     :  p95={v(cl,'p95')}  p99={v(cl,'p99')}")
PYEOF
}

compare_runs() {
  local id1="$1" id2="$2"
  local label1="${3:-run $id1}" label2="${4:-run $id2}"

  download_run "$id1"
  echo ""
  download_run "$id2"
  echo ""
  echo "=== Comparison: $label1 vs $label2 ==="

  python3 - "$RESULTS_DIR/cloud-run-${id1}-timeseries.json" \
             "$RESULTS_DIR/cloud-run-${id2}-timeseries.json" \
             "$label1" "$label2" <<'PYEOF'
import json, sys

ts1 = json.load(open(sys.argv[1]))
ts2 = json.load(open(sys.argv[2]))
l1, l2 = sys.argv[3], sys.argv[4]

def val(ts, section, key):
    return ts.get(section, {}).get(key)

def pct_diff(a, b):
    if a is None or b is None or a == 0: return "n/a"
    diff = (b - a) / a * 100
    sign = "+" if diff > 0 else ""
    return f"{sign}{diff:.0f}%"

metrics = [
    ("http_req_duration p95 (ms)", "http_req_duration_ms", "p95"),
    ("http_req_duration p99 (ms)", "http_req_duration_ms", "p99"),
    ("http_req_failed rate",       "http_req_failed_rate", "rate"),
    ("http_reqs/sec",              "http_reqs_per_sec",    "rps_avg"),
    ("claim_duration p95 (ms)",    "claim_duration_ms",    "p95"),
]

col = max(len(m[0]) for m in metrics) + 2
print(f"  {'Metric':<{col}} {l1:>12}  {l2:>12}  {'Delta':>8}")
print("  " + "-" * (col + 38))
for name, path, agg in metrics:
    v1 = val(ts1, path, agg)
    v2 = val(ts2, path, agg)
    s1 = f"{v1:.1f}" if v1 is not None else "n/a"
    s2 = f"{v2:.1f}" if v2 is not None else "n/a"
    delta = pct_diff(v1, v2)
    print(f"  {name:<{col}} {s1:>12}  {s2:>12}  {delta:>8}")
PYEOF
}

if [[ $# -ge 2 ]]; then
  compare_runs "$1" "$2" "${3:-}" "${4:-}"
elif [[ $# -eq 1 ]]; then
  download_run "$1"
else
  echo "=== Recent runs in project $PROJECT_ID ==="
  api_get "cloud/v5/projects/$PROJECT_ID/test_runs" | python3 -c "
import sys, json
d = json.load(sys.stdin)
runs = d.get('value', [])
if not runs:
    print('  No runs found.')
    sys.exit(0)
print(f\"  {'ID':<12} {'Script':<30} {'Status':<10} {'VUs':<6} {'Started'}\")
print('  ' + '-'*75)
for r in sorted(runs, key=lambda x: x.get('started',''), reverse=True):
    status = {3:'finished', 2:'running', 4:'aborted'}.get(r.get('run_status'), str(r.get('run_status')))
    started = r.get('started', 'unknown')[:19]
    raw = (r.get('script') or '') if isinstance(r.get('script'), str) else ''
    # Script starts with: // tests/load/shielded.js — extract filename
    first = raw.split('\n')[0].lstrip('/ ').strip()
    script = first.split('/')[-1][:29]
    vus = r.get('vus', '')
    print(f\"  {r['id']:<12} {script:<30} {status:<10} {vus:<6} {started}\")
"
  echo ""
  echo "Download a run   : $0 <run_id>"
  echo "Compare two runs : $0 <run_id1> <run_id2> [label1] [label2]"
fi
