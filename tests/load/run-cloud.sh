#!/usr/bin/env bash
# tests/load/run-cloud.sh
# Cloud-scale benchmark: shielded vs unshielded via Grafana Cloud k6.
# Usage: ./tests/load/run-cloud.sh [spike|ramp|sustained]  (default: spike)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$REPO_ROOT/.env.cloud"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found. Copy .env.cloud.example and fill in cloud credentials."
  exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

: "${DB1_URL:?DB1_URL must be set in .env.cloud}"
: "${DB2_URL:?DB2_URL must be set in .env.cloud}"
: "${DB1_KEY:?DB1_KEY must be set in .env.cloud}"
: "${DB2_KEY:?DB2_KEY must be set in .env.cloud}"
: "${K6_CLOUD_TOKEN:?K6_CLOUD_TOKEN must be set in .env.cloud}"

PROJECT_ID=6883841

latest_run_id() {
  curl -sf "https://api.k6.io/cloud/v5/projects/$PROJECT_ID/test_runs" \
    -H "Authorization: Token $K6_CLOUD_TOKEN" | \
    python3 -c "
import sys, json
runs = json.load(sys.stdin)['value']
print(sorted(runs, key=lambda r: r.get('started',''), reverse=True)[0]['id'])
"
}

SCENARIO="${1:-spike}"
echo "=== Cloud load test: $SCENARIO scenario ($(date)) ==="

# --- REST helpers ---
db1_post() { curl -sf -X POST "$DB1_URL/rest/v1/$1" \
  -H "apikey: $DB1_KEY" -H "Authorization: Bearer $DB1_KEY" \
  -H "Content-Type: application/json" -H "Prefer: $2" -d "$3"; }

db1_delete() { curl -sf -X DELETE "$DB1_URL/rest/v1/$1" \
  -H "apikey: $DB1_KEY" -H "Authorization: Bearer $DB1_KEY"; }

db2_delete() { curl -sf -X DELETE "$DB2_URL/rest/v1/$1" \
  -H "apikey: $DB2_KEY" -H "Authorization: Bearer $DB2_KEY"; }

setup_db1() {
  echo "--- Setting up load_test pool on cloud DB1 ---"

  db1_post "engine_config" "resolution=ignore-duplicates" \
    '{"pool_id":"load_test","batch_size":100,"visibility_timeout_sec":45,"max_retries":10,"is_active":true}'

  db1_delete "inventory_slots?pool_id=eq.load_test"

  echo "    Inserting 500k inventory slots (50 batches of 10k)..."
  BATCH=$(python3 -c "import json; print(json.dumps([{'pool_id':'load_test','status':'AVAILABLE'}]*10000))")
  for i in $(seq 1 50); do
    db1_post "inventory_slots" "return=minimal" "$BATCH" > /dev/null
    printf "    %d/50\r" "$i"
  done
  echo ""

  echo "    Creating claim sequence..."
  db1_post "rpc/reset_claim_sequence" "return=minimal" \
    '{"p_pool_id":"load_test","p_start":1}'
}

cleanup() {
  echo "--- Cleaning up between runs ---"
  db1_delete "inventory_slots?pool_id=eq.load_test"
  db2_delete "confirmed_tickets?pool_id=eq.load_test"
}

teardown() {
  echo "--- Tearing down ---"
  db1_delete "inventory_slots?pool_id=eq.load_test"
  db1_delete "engine_metrics?pool_id=eq.load_test"
  db2_delete "confirmed_tickets?pool_id=eq.load_test"
}

setup_db1

echo "--- Running SHIELDED scenario (cloud scale) ---"
SHIELDED_EXIT=0
k6 cloud run \
  -e SCENARIO="$SCENARIO" \
  -e CLOUD_SCALE=1 \
  -e DB1_URL="$DB1_URL" \
  -e DB1_KEY="$DB1_KEY" \
  "$SCRIPT_DIR/shielded.js" || SHIELDED_EXIT=$?
SHIELDED_RUN_ID=$(latest_run_id)

cleanup
setup_db1

echo "--- Running UNSHIELDED scenario (cloud scale) ---"
UNSHIELDED_EXIT=0
k6 cloud run \
  -e SCENARIO="$SCENARIO" \
  -e CLOUD_SCALE=1 \
  -e DB2_URL="$DB2_URL" \
  -e DB2_KEY="$DB2_KEY" \
  "$SCRIPT_DIR/unshielded.js" || UNSHIELDED_EXIT=$?
UNSHIELDED_RUN_ID=$(latest_run_id)

teardown

echo ""
echo "=== Results in Grafana Cloud k6 dashboard: https://app.k6.io ==="
echo "    Shielded   : run $SHIELDED_RUN_ID   exit=$SHIELDED_EXIT  (0=pass, 99=thresholds crossed)"
echo "    Unshielded : run $UNSHIELDED_RUN_ID  exit=$UNSHIELDED_EXIT  (99 expected — DB2 saturates)"
echo ""
echo "Compare:"
echo "    ./tests/load/download-results.sh $SHIELDED_RUN_ID $UNSHIELDED_RUN_ID shielded unshielded"
