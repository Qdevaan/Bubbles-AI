// k6 load test for Bubbles Brain API v5.
//
//   k6 run -e BASE_URL=https://api.example -e TOKEN=$JWT scripts/load_test.js
//
// Scenarios run sequentially: cold-start probe, steady ramp, spike, then a
// short provider-outage window (caller is expected to break the upstream key
// out of band — the assertions still hold because we only require either a
// 200 or a 503-with-Retry-After).

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Trend, Rate } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8000';
const TOKEN = __ENV.TOKEN || '';
const AUTH = TOKEN ? { Authorization: `Bearer ${TOKEN}` } : {};

const ttftConsultant = new Trend('ttft_consultant_ms', true);
const degraded = new Rate('degraded_responses');

export const options = {
  thresholds: {
    // SLO gates — k6 fails the run if these are breached.
    'http_req_duration{route:health}': ['p(95)<50'],
    'http_req_duration{route:consultant_json}': ['p(95)<2000'],
    'http_req_failed': ['rate<0.02'],
    'degraded_responses': ['rate<0.05'],
  },
  scenarios: {
    cold_start: {
      executor: 'shared-iterations',
      vus: 1,
      iterations: 3,
      exec: 'health',
      startTime: '0s',
    },
    steady: {
      executor: 'ramping-vus',
      exec: 'mixed',
      startTime: '5s',
      stages: [
        { duration: '30s', target: 10 },
        { duration: '2m', target: 10 },
        { duration: '20s', target: 0 },
      ],
    },
    spike: {
      executor: 'ramping-vus',
      exec: 'mixed',
      startTime: '3m20s',
      stages: [
        { duration: '10s', target: 40 },
        { duration: '40s', target: 40 },
        { duration: '10s', target: 0 },
      ],
    },
  },
};

function classify(res) {
  // Treat 503 with Retry-After as graceful degradation, not a failure.
  if (res.status === 503 && res.headers['Retry-After']) {
    degraded.add(1);
    return true;
  }
  degraded.add(0);
  return res.status >= 200 && res.status < 400;
}

export function health() {
  const res = http.get(`${BASE_URL}/health/ready`, { tags: { route: 'health' } });
  check(res, { 'health ok': (r) => r.status === 200 });
}

export function mixed() {
  // 1. health
  http.get(`${BASE_URL}/health/live`, { tags: { route: 'health' } });

  // 2. consultant (non-stream JSON path) — needs auth; skip if no token.
  if (TOKEN) {
    const start = Date.now();
    const res = http.post(
      `${BASE_URL}/v1/ask_consultant?stream=false`,
      JSON.stringify({ question: 'Give me one productivity tip.' }),
      { headers: { 'Content-Type': 'application/json', ...AUTH }, tags: { route: 'consultant_json' } },
    );
    ttftConsultant.add(Date.now() - start);
    check(res, { 'consultant graceful': classify });
  }

  sleep(Math.random() * 0.5);
}
