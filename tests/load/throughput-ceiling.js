// tests/load/throughput-ceiling.js
// Throughput ceiling test: stepped VU ramp to find max rps of claim_resource_and_queue.
// Run via: ./tests/load/run-throughput-ceiling.sh

import http from 'k6/http';
import { check } from 'k6';
import {
  DB1_URL, DB1_HEADERS, POOL_ID,
  soldOutCounter, claimDuration,
} from './lib/config.js';

// Stepped VU ramp: 100 → 200 → 500 → 1000 → 2000, 60s hold per step.
// No think time — each VU fires as fast as the server responds.
export const options = {
  scenarios: {
    throughput_ceiling: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '10s',  target: 100 },   // ramp to 100
        { duration: '60s',  target: 100 },   // hold
        { duration: '10s',  target: 200 },   // ramp to 200
        { duration: '60s',  target: 200 },   // hold
        { duration: '10s',  target: 500 },   // ramp to 500
        { duration: '60s',  target: 500 },   // hold
        { duration: '10s',  target: 1000 },  // ramp to 1000
        { duration: '60s',  target: 1000 },  // hold
        { duration: '10s',  target: 2000 },  // ramp to 2000
        { duration: '60s',  target: 2000 },  // hold
        { duration: '10s',  target: 0 },     // ramp down
      ],
    },
  },
  thresholds: {
    http_req_failed:   ['rate<0.05'],    // <5% errors (generous — we expect saturation)
    http_req_duration: ['p(95)<2000'],   // p95 under 2s (generous — measuring ceiling)
  },
  cloud: {
    distribution: {
      ashburn: { loadZone: 'amazon:us:ashburn', percent: 100 },
    },
  },
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

  check(res, {
    'status is 200': (r) => r.status === 200,
  });

  if (res.body === 'null' || res.body === '') {
    soldOutCounter.add(1);
  }

  // No sleep — maximize per-VU throughput to find the true ceiling.
}
