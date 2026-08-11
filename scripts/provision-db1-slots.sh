#!/usr/bin/env bash
# scripts/provision-db1-slots.sh
# Provision DB1 inventory_slots for each DB2 event.
# Usage: ./scripts/provision-db1-slots.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env.cloud"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found."
  exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

: "${DB1_URL:?DB1_URL must be set}"
: "${DB1_KEY:?DB1_KEY must be set}"
: "${DB2_URL:?DB2_URL must be set}"
: "${DB2_KEY:?DB2_KEY must be set}"

db1_post() {
  curl -sf -X POST "$DB1_URL/rest/v1/$1" \
    -H "apikey: $DB1_KEY" -H "Authorization: Bearer $DB1_KEY" \
    -H "Content-Type: application/json" -H "Prefer: $2" -d "$3"
}

db1_delete() {
  curl -sf -X DELETE "$DB1_URL/rest/v1/$1" \
    -H "apikey: $DB1_KEY" -H "Authorization: Bearer $DB1_KEY"
}

echo "=== Provisioning DB1 slots for DB2 events ==="

# Fetch events from DB2
EVENTS=$(curl -sf "$DB2_URL/rest/v1/events?select=id,name,total_tickets" \
  -H "apikey: $DB2_KEY" -H "Authorization: Bearer $DB2_KEY")

echo "$EVENTS" | python3 -c "
import sys, json
events = json.load(sys.stdin)
for e in events:
    print(f\"  {e['name']}: {e['total_tickets']} tickets (pool_id={e['id']})\")"

# Process each event
echo "$EVENTS" | python3 -c "
import sys, json
events = json.load(sys.stdin)
for e in events:
    print(f\"{e['id']} {e['total_tickets']}\")
" | while read -r EVENT_ID TOTAL_TICKETS; do
  echo ""
  echo "--- $EVENT_ID ($TOTAL_TICKETS tickets) ---"

  # Ensure engine_config exists for this pool
  db1_post "engine_config" "resolution=ignore-duplicates" \
    "{\"pool_id\":\"$EVENT_ID\",\"batch_size\":100,\"visibility_timeout_sec\":45,\"max_retries\":10,\"is_active\":true}" > /dev/null

  # Delete existing slots for this pool (idempotent)
  db1_delete "inventory_slots?pool_id=eq.$EVENT_ID" > /dev/null 2>&1 || true

  # Insert slots in batches of 10,000
  REMAINING=$TOTAL_TICKETS
  INSERTED=0
  while [ "$REMAINING" -gt 0 ]; do
    BATCH_SIZE=$((REMAINING > 10000 ? 10000 : REMAINING))
    BATCH=$(python3 -c "import json; print(json.dumps([{'pool_id':'$EVENT_ID','status':'AVAILABLE'}]*$BATCH_SIZE))")
    db1_post "inventory_slots" "return=minimal" "$BATCH" > /dev/null
    INSERTED=$((INSERTED + BATCH_SIZE))
    REMAINING=$((REMAINING - BATCH_SIZE))
    printf "    Inserted %d/%d\r" "$INSERTED" "$TOTAL_TICKETS"
  done
  echo ""

  # Assign sequential positions
  echo "    Assigning sequential positions..."
  db1_post "rpc/assign_seq_positions" "return=representation" \
    "{\"p_pool_id\":\"$EVENT_ID\"}" > /dev/null

  # Reset claim sequence
  echo "    Resetting claim sequence..."
  db1_post "rpc/reset_claim_sequence" "return=minimal" \
    "{\"p_pool_id\":\"$EVENT_ID\",\"p_start\":1}" > /dev/null

  echo "    Done."
done

echo ""
echo "=== Provisioning complete ==="
