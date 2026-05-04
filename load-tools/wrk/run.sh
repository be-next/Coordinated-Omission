#!/usr/bin/env bash
# Closed-loop runner — wrk (Will Glozer's original).
# Negative example: another closed-loop tool whose default mode hides the tail.
# To get HDR-quality output you would need wrk2 (Gil Tene's fork), see README.

set -euo pipefail

SCENARIO="${1:-02-single-hiccup}"
HOST="${HOST:-http://127.0.0.1:8080}"
ENDPOINT="${ENDPOINT:-/api}"
DURATION="${DURATION:-60s}"
THREADS="${THREADS:-2}"
CONNECTIONS="${CONNECTIONS:-10}"

OUT_DIR="results/${SCENARIO}/wrk"
mkdir -p "${OUT_DIR}"

echo "[wrk] sanity check: ${HOST}/healthy"
curl -fsS "${HOST}/healthy" >/dev/null

echo "[wrk] running: -d ${DURATION} -t ${THREADS} -c ${CONNECTIONS} ${HOST}${ENDPOINT}"
wrk -d "${DURATION}" -t "${THREADS}" -c "${CONNECTIONS}" \
    --latency \
    "${HOST}${ENDPOINT}" \
    > "${OUT_DIR}/wrk.txt" 2>&1

echo "[wrk] done — see ${OUT_DIR}/"
