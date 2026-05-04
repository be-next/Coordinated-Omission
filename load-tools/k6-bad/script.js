// BAD — closed-loop k6 scenario. Susceptible to coordinated omission.
//
// 10 virtual users each loop as fast as the server allows. When the server
// stalls, the loop stalls with it: no new requests are issued during the
// pause, so the report says "tail latency is fine" while a real user base
// would have piled up behind the gate.
//
// This is the negative example the blog post warns against.

import http from 'k6/http';

export const options = {
  scenarios: {
    susceptible: {
      executor: 'constant-vus',
      vus: 10,
      duration: '60s',
    },
  },
};

export default function () {
  http.get(`${__ENV.HOST}/api`);
}
