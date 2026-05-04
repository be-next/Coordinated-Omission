#!/usr/bin/env bash
# Open-loop runner — wrk2 (Gil Tene's fork of wrk).
# Drives a constant arrival rate and applies the intended-start-time
# correction. This is the honest reference.

set -euo pipefail

SCENARIO="${1:-02-single-hiccup}"
HOST="${HOST:-http://127.0.0.1:8080}"
ENDPOINT="${ENDPOINT:-/api}"
RATE="${RATE:-1000}"
DURATION="${DURATION:-60s}"
THREADS="${THREADS:-4}"
CONNECTIONS="${CONNECTIONS:-50}"

OUT_DIR="results/${SCENARIO}/wrk2"
mkdir -p "${OUT_DIR}"

echo "[wrk2] sanity check: ${HOST}/healthy"
curl -fsS "${HOST}/healthy" >/dev/null

echo "[wrk2] running: -R ${RATE} -d ${DURATION} -t ${THREADS} -c ${CONNECTIONS} ${HOST}${ENDPOINT}"
wrk2 -R "${RATE}" -d "${DURATION}" -t "${THREADS}" -c "${CONNECTIONS}" \
     --latency \
     -s "$(dirname "$0")/hdr-dump.lua" \
     "${HOST}${ENDPOINT}" \
     > "${OUT_DIR}/wrk2.txt" 2>&1

# wrk2 prints the percentile distribution to stdout when --latency is set;
# the lua hook below also writes a parseable HDR file.
[ -f wrk2.hdr ] && mv wrk2.hdr "${OUT_DIR}/wrk2.hdr" || true

echo "[wrk2] done — see ${OUT_DIR}/"
