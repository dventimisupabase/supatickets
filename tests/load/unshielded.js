// tests/load/unshielded.js
// Unshielded scenario: load hits DB2's finalize_transaction RPC directly.
// This is the "before DB1" baseline — the permanent database absorbs the full burst.

import http from 'k6/http';
import { check, sleep } from 'k6';
import {
  DB2_URL, DB2_HEADERS, POOL_ID,
  uuidv4, claimDuration,
  getScenario, THRESHOLDS, CLOUD_OPTIONS,
} from './lib/config.js';

export const options = {
  scenarios: getScenario(),
  thresholds: THRESHOLDS,
  cloud: CLOUD_OPTIONS,
};

export default function () {
  // Fresh UUID every iteration — no ON CONFLICT shortcut, every request is a real insert.
  const resourceId = uuidv4();
  const userId = `vu_${__VU}_iter_${__ITER}`;

  const start = Date.now();
  const res = http.post(
    `${DB2_URL}/rest/v1/rpc/finalize_transaction`,
    JSON.stringify({
      p_payload: {
        resource_id: resourceId,
        pool_id: POOL_ID,
        user_id: userId,
      },
    }),
    { headers: DB2_HEADERS },
  );
  claimDuration.add(Date.now() - start);

  check(res, {
    'status is 2xx': (r) => r.status >= 200 && r.status < 300,
  });

  sleep(0.01);
}
