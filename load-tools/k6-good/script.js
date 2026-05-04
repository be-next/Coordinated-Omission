// GOOD — open-loop k6 scenario. Coordinated-omission-aware.
//
// k6 schedules 1 000 requests per second regardless of how fast the server
// is responding. When the server stalls, the next requests stack up in the
// VU pool and contribute their queueing time to the reported latency —
// the intended-start-time correction.
//
// IMPORTANT: maxVUs must be large enough to absorb the slow-down peak.
// During a 1 s stall at 1 000 rps, ~1 000 requests pile up. If maxVUs is
// undersized, k6 reports `dropped_iterations` and silently *omits* the
// queued requests — partially reintroducing the very phenomenon that
// constant-arrival-rate is supposed to prevent. We pre-allocate generously.
//
// This is the positive example the blog post recommends.

import http from 'k6/http';

export const options = {
  scenarios: {
    honest: {
      executor: 'constant-arrival-rate',
      rate: 1000,
      timeUnit: '1s',
      duration: '60s',
      preAllocatedVUs: 1500,
      maxVUs: 5000,
    },
  },
};

export default function () {
  http.get(`${__ENV.HOST}/api`);
}
