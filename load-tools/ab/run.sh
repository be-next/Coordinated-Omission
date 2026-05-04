#!/usr/bin/env bash
# Closed-loop runner — Apache Bench.
# By design ab cannot drive a constant arrival rate; this is the negative
# example that demonstrates coordinated omission.

set -euo pipefail

SCENARIO="${1:-02-single-hiccup}"
HOST="${HOST:-http://127.0.0.1:8080}"
ENDPOINT="${ENDPOINT:-/api}"
# With baseline latency 10 ms and concurrency 10, ab tops out around 1 000 rps,
# so 60 000 requests take ~60 s — long enough to span the hiccup at t=30 s.
REQUESTS="${REQUESTS:-60000}"
CONCURRENCY="${CONCURRENCY:-10}"

OUT_DIR="results/${SCENARIO}/ab"
mkdir -p "${OUT_DIR}"

echo "[ab] sanity check: ${HOST}/healthy"
curl -fsS "${HOST}/healthy" >/dev/null

echo "[ab] running: -n ${REQUESTS} -c ${CONCURRENCY} ${HOST}${ENDPOINT}"
ab -n "${REQUESTS}" -c "${CONCURRENCY}" \
   -e "${OUT_DIR}/percentiles.csv" \
   -g "${OUT_DIR}/timeseries.tsv" \
   "${HOST}${ENDPOINT}" \
   > "${OUT_DIR}/ab.txt" 2>&1

echo "[ab] done — see ${OUT_DIR}/"
