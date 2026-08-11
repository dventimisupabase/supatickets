// tests/load/lib/config.js
import { Counter, Trend } from 'k6/metrics';

// --- Connection config (override with -e flags or env vars) ---
export const DB1_URL = __ENV.DB1_URL || 'http://127.0.0.1:54341';
export const DB2_URL = __ENV.DB2_URL || 'http://127.0.0.1:54441';

// JWT service-role keys — local dev defaults from `supabase status --output env`
const DB1_KEY = __ENV.DB1_KEY ||
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';
const DB2_KEY = __ENV.DB2_KEY ||
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';

export const DB1_HEADERS = {
  'Content-Type': 'application/json',
  'apikey': DB1_KEY,
  'Authorization': `Bearer ${DB1_KEY}`,
};

export const DB2_HEADERS = {
  'Content-Type': 'application/json',
  'apikey': DB2_KEY,
  'Authorization': `Bearer ${DB2_KEY}`,
};

export const POOL_ID = 'load_test';

// --- UUID helper ---
// k6 doesn't ship crypto.randomUUID(); use this instead.
export function uuidv4() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

// --- Custom metrics ---
// Track sold-out responses separately from errors.
export const soldOutCounter = new Counter('sold_out_responses');
export const claimDuration  = new Trend('claim_duration_ms', true);

// --- Scenario configurations ---
// Select with: k6 run -e SCENARIO=spike shielded.js
//              k6 run -e SCENARIO=ramp  shielded.js
//              k6 run -e SCENARIO=sustained shielded.js
const SCENARIO = __ENV.SCENARIO || 'spike';
const CLOUD_SCALE = __ENV.CLOUD_SCALE === '1';

// --- Local scenarios (default) — capped at 200 VUs for local PostgREST ---
const SPIKE = {
  executor: 'ramping-vus',
  stages: [
    { duration: '5s',  target: 200 },
    { duration: '60s', target: 200 },
    { duration: '5s',  target: 0 },
  ],
};
const RAMP = {
  executor: 'ramping-vus',
  stages: [
    { duration: '30s', target: 25 },
    { duration: '30s', target: 50 },
    { duration: '30s', target: 100 },
    { duration: '30s', target: 200 },
    { duration: '30s', target: 0 },
  ],
};
const SUSTAINED = { executor: 'constant-vus', vus: 100, duration: '3m' };

// --- Cloud scenarios — capped at 100 VUs (Grafana Cloud k6 free tier limit) ---
const SPIKE_CLOUD = {
  executor: 'ramping-vus',
  stages: [
    { duration: '5s',  target: 500 },
    { duration: '60s', target: 500 },
    { duration: '5s',  target: 0 },
  ],
};
const RAMP_CLOUD = {
  executor: 'ramping-vus',
  stages: [
    { duration: '30s', target: 50 },
    { duration: '30s', target: 100 },
    { duration: '30s', target: 250 },
    { duration: '30s', target: 500 },
    { duration: '30s', target: 0 },
  ],
};
const SUSTAINED_CLOUD = { executor: 'constant-vus', vus: 300, duration: '3m' };

const LOCAL_SCENARIOS  = { spike: SPIKE,       ramp: RAMP,       sustained: SUSTAINED       };
const CLOUD_SCENARIOS  = { spike: SPIKE_CLOUD, ramp: RAMP_CLOUD, sustained: SUSTAINED_CLOUD };

export function getScenario() {
  const dict = CLOUD_SCALE ? CLOUD_SCENARIOS : LOCAL_SCENARIOS;
  const s = dict[SCENARIO];
  if (!s) throw new Error(`Unknown SCENARIO=${SCENARIO}. Use spike, ramp, or sustained.`);
  return { [SCENARIO]: s };
}

// --- Shared thresholds ---
// Both shielded and unshielded use the same thresholds so failures are comparable.
export const THRESHOLDS = {
  http_req_failed:   ['rate<0.01'],   // <1% HTTP errors (5xx, network failures)
  http_req_duration: ['p(95)<500'],   // p95 under 500ms (generous; we're measuring shape, not absolute)
};

// --- Cloud options ---
// Pin load generators to us-east-1 (Ashburn) to co-locate with Supabase project.
export const CLOUD_OPTIONS = CLOUD_SCALE
  ? { distribution: { ashburn: { loadZone: 'amazon:us:ashburn', percent: 100 } } }
  : {};
