#!/usr/bin/env bash
# Closed-loop runner — hey.
# Convenient single-binary load tester, fixed concurrency, no rate control.
# Reports a percentile distribution; not honest under server slowdowns.

set -euo pipefail

SCENARIO="${1:-02-single-hiccup}"
HOST="${HOST:-http://127.0.0.1:8080}"
ENDPOINT="${ENDPOINT:-/api}"
REQUESTS="${REQUESTS:-60000}"
CONCURRENCY="${CONCURRENCY:-10}"

OUT_DIR="results/${SCENARIO}/hey"
mkdir -p "${OUT_DIR}"

echo "[hey] sanity check: ${HOST}/healthy"
curl -fsS "${HOST}/healthy" >/dev/null

echo "[hey] running: -n ${REQUESTS} -c ${CONCURRENCY} ${HOST}${ENDPOINT}"
hey -n "${REQUESTS}" -c "${CONCURRENCY}" \
    -o csv \
    "${HOST}${ENDPOINT}" \
    > "${OUT_DIR}/samples.csv" 2> "${OUT_DIR}/hey.txt"

# Run again without -o csv to get the human-readable summary.
hey -n 1000 -c "${CONCURRENCY}" \
    "${HOST}${ENDPOINT}" \
    >> "${OUT_DIR}/hey.txt" 2>&1 || true

echo "[hey] done — see ${OUT_DIR}/"
