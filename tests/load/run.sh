#!/usr/bin/env bash
# tests/load/run.sh
# Full benchmark: shielded vs unshielded, all three scenario types.
# Usage: ./tests/load/run.sh [spike|ramp|sustained]  (default: spike)

set -euo pipefail

SCENARIO="${1:-spike}"
TIMESTAMP=$(date +%s)
RESULTS_DIR="tests/load/results"
mkdir -p "$RESULTS_DIR"

DB1_POSTGRES="postgresql://postgres:postgres@127.0.0.1:54342/postgres"
DB2_POSTGRES="postgresql://postgres:postgres@127.0.0.1:54442/postgres"

echo "=== Load test: $SCENARIO scenario ($(date)) ==="

echo "--- Setting up load_test pool on DB1 ---"
psql "$DB1_POSTGRES" -f tests/load/setup.sql

echo "--- Running SHIELDED scenario ---"
k6 run -e SCENARIO="$SCENARIO" \
  --out json="$RESULTS_DIR/shielded-${SCENARIO}-${TIMESTAMP}.json" \
  tests/load/shielded.js 2>&1 | tee "$RESULTS_DIR/shielded-${SCENARIO}-${TIMESTAMP}.txt"

echo "--- Cleaning up between runs ---"
psql "$DB1_POSTGRES" -c "DELETE FROM inventory_slots WHERE pool_id = 'load_test';"
psql "$DB2_POSTGRES" -c "DELETE FROM confirmed_tickets WHERE pool_id = 'load_test';"
psql "$DB1_POSTGRES" -f tests/load/setup.sql

echo "--- Running UNSHIELDED scenario ---"
k6 run -e SCENARIO="$SCENARIO" \
  --out json="$RESULTS_DIR/unshielded-${SCENARIO}-${TIMESTAMP}.json" \
  tests/load/unshielded.js 2>&1 | tee "$RESULTS_DIR/unshielded-${SCENARIO}-${TIMESTAMP}.txt"

echo "--- Tearing down ---"
psql "$DB1_POSTGRES" -f tests/load/teardown.sql
psql "$DB2_POSTGRES" -c "DELETE FROM confirmed_tickets WHERE pool_id = 'load_test';"

echo ""
echo "=== Results ==="
echo "Shielded:   $RESULTS_DIR/shielded-${SCENARIO}-${TIMESTAMP}.txt"
echo "Unshielded: $RESULTS_DIR/unshielded-${SCENARIO}-${TIMESTAMP}.txt"
echo ""
echo "Key metric to compare: http_req_duration p95 and p99"
