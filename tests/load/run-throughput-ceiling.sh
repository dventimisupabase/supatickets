#!/usr/bin/env bash
# tests/load/run-throughput-ceiling.sh
# Throughput ceiling test: find max rps of claim_resource_and_queue on managed Supabase.
# Usage: ./tests/load/run-throughput-ceiling.sh

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
: "${DB1_KEY:?DB1_KEY must be set in .env.cloud}"
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

# --- REST helpers (same pattern as run-cloud.sh) ---
db1_post() { curl -sf -X POST "$DB1_URL/rest/v1/$1" \
  -H "apikey: $DB1_KEY" -H "Authorization: Bearer $DB1_KEY" \
  -H "Content-Type: application/json" -H "Prefer: $2" -d "$3"; }

db1_delete() { curl -sf -X DELETE "$DB1_URL/rest/v1/$1" \
  -H "apikey: $DB1_KEY" -H "Authorization: Bearer $DB1_KEY"; }

echo "=== Throughput ceiling test ($(date)) ==="

# --- Setup: 1M inventory slots ---
echo "--- Setting up load_test pool on cloud DB1 (1M slots) ---"

db1_post "engine_config" "resolution=ignore-duplicates" \
  '{"pool_id":"load_test","batch_size":100,"visibility_timeout_sec":45,"max_retries":10,"is_active":true}'

db1_delete "inventory_slots?pool_id=eq.load_test"

echo "    Inserting 1M inventory slots (100 batches of 10k)..."
BATCH=$(python3 -c "import json; print(json.dumps([{'pool_id':'load_test','status':'AVAILABLE'}]*10000))")
for i in $(seq 1 100); do
  db1_post "inventory_slots" "return=minimal" "$BATCH" > /dev/null
  printf "    %d/100\r" "$i"
done
echo ""

# Verify slot count
SLOT_COUNT=$(curl -sf "$DB1_URL/rest/v1/inventory_slots?pool_id=eq.load_test&status=eq.AVAILABLE&select=count" \
  -H "apikey: $DB1_KEY" -H "Authorization: Bearer $DB1_KEY" \
  -H "Prefer: count=exact" -H "Range-Unit: items" -H "Range: 0-0" \
  -I 2>/dev/null | grep -i content-range | grep -oE '[0-9]+$' || echo "unknown")
echo "    Slot count: $SLOT_COUNT"

# --- Assign sequential positions ---
echo "    Assigning sequential positions..."
db1_post "rpc/assign_seq_positions" "return=representation" \
  '{"p_pool_id":"load_test"}'
echo ""

# --- Create/reset claim sequence ---
echo "    Resetting claim sequence..."
db1_post "rpc/reset_claim_sequence" "return=minimal" \
  '{"p_pool_id":"load_test","p_start":1}'

# --- Run ---
echo "--- Running throughput ceiling test (k6 cloud) ---"
RUN_EXIT=0
k6 cloud run \
  -e DB1_URL="$DB1_URL" \
  -e DB1_KEY="$DB1_KEY" \
  "$SCRIPT_DIR/throughput-ceiling.js" || RUN_EXIT=$?
RUN_ID=$(latest_run_id)

# --- Teardown ---
echo "--- Tearing down ---"
db1_delete "inventory_slots?pool_id=eq.load_test"
db1_delete "engine_metrics?pool_id=eq.load_test"

echo ""
echo "=== Results ==="
echo "    Run ID : $RUN_ID"
echo "    Exit   : $RUN_EXIT  (0=pass, 99=thresholds crossed)"
echo "    Dashboard: https://app.k6.io"
echo ""
echo "Download results:"
echo "    ./tests/load/download-results.sh $RUN_ID"
