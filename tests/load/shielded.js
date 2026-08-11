// tests/load/shielded.js
// Shielded scenario: load hits DB1's claim RPC.
// DB2 is written to at a metered rate by the bridge worker — it never sees the burst.

import http from 'k6/http';
import { check, sleep } from 'k6';
import {
  DB1_URL, DB1_HEADERS, POOL_ID,
  uuidv4, soldOutCounter, claimDuration,
  getScenario, THRESHOLDS, CLOUD_OPTIONS,
} from './lib/config.js';

export const options = {
  scenarios: getScenario(),
  thresholds: THRESHOLDS,
  cloud: CLOUD_OPTIONS,
};

export default function () {
  const userId = `vu_${__VU}_iter_${__ITER}`;

  const start = Date.now();
  const res = http.post(
    `${DB1_URL}/rest/v1/rpc/claim_resource_and_queue`,
    JSON.stringify({ p_pool_id: POOL_ID, p_user_id: userId }),
    { headers: DB1_HEADERS },
  );
  claimDuration.add(Date.now() - start);

  // HTTP 200 is always expected — NULL body means sold out, UUID means claimed.
  check(res, {
    'status is 200': (r) => r.status === 200,
  });

  if (res.body === 'null' || res.body === '') {
    soldOutCounter.add(1);
  }

  sleep(0.01);
}
