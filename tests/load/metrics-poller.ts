// tests/load/metrics-poller.ts
// Run with:
//   deno run --allow-net --allow-env tests/load/metrics-poller.ts
//
// Prints CSV to stdout. Redirect to a file:
//   deno run --allow-net --allow-env tests/load/metrics-poller.ts \
//     > tests/load/results/metrics-$(date +%s).csv

import { Client } from 'https://deno.land/x/postgres@v0.19.3/mod.ts';

const DB1_URL = Deno.env.get('DB1_POSTGRES_URL') ??
  'postgresql://postgres:postgres@127.0.0.1:54342/postgres';
const DB2_URL = Deno.env.get('DB2_POSTGRES_URL') ??
  'postgresql://postgres:postgres@127.0.0.1:54442/postgres';

const POLL_INTERVAL_MS = 5_000;
const POOL_ID = Deno.env.get('POOL_ID') ?? 'load_test';

const db1 = new Client(DB1_URL);
const db2 = new Client(DB2_URL);

await db1.connect();
await db2.connect();

// CSV header
console.log('timestamp,db1_queue_depth,db1_dlq_depth,db1_available_slots,db1_reserved_slots,db1_consumed_slots,db2_confirmed_total');

async function poll() {
  const ts = new Date().toISOString();

  // Latest engine_metrics row for the load_test pool
  const metricsResult = await db1.queryObject<{
    queue_depth: number;
    dlq_depth: number;
    available_slots: number;
    reserved_slots: number;
    consumed_slots: number;
  }>(`
    SELECT queue_depth, dlq_depth, available_slots, reserved_slots, consumed_slots
    FROM engine_metrics
    WHERE pool_id = $1
    ORDER BY captured_at DESC
    LIMIT 1
  `, [POOL_ID]);

  const m = metricsResult.rows[0];

  // Total confirmed tickets on DB2 for this pool
  const confirmedResult = await db2.queryObject<{ count: string }>(`
    SELECT COUNT(*)::TEXT AS count
    FROM confirmed_tickets
    WHERE pool_id = $1
  `, [POOL_ID]);

  const confirmedTotal = confirmedResult.rows[0]?.count ?? '0';

  if (m) {
    console.log([
      ts,
      m.queue_depth,
      m.dlq_depth,
      m.available_slots,
      m.reserved_slots,
      m.consumed_slots,
      confirmedTotal,
    ].join(','));
  } else {
    console.log(`${ts},0,0,0,0,0,${confirmedTotal}`);
  }
}

// Poll on interval until interrupted
while (true) {
  try {
    await poll();
  } catch (err) {
    console.error(`# poll error: ${err}`);
  }
  await new Promise((r) => setTimeout(r, POLL_INTERVAL_MS));
}
