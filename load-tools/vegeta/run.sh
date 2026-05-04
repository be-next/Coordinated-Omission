#!/usr/bin/env bash
# Open-loop runner — Vegeta.
# Drives a constant arrival rate and records every request, including the
# ones that pile up behind a slowdown. The honest reference for this
# repository now that wrk2 cannot be built on Apple Silicon.

set -euo pipefail

SCENARIO="${1:-02-single-hiccup}"
HOST="${HOST:-http://127.0.0.1:8080}"
ENDPOINT="${ENDPOINT:-/api}"
RATE="${RATE:-1000}"
DURATION="${DURATION:-60s}"

# Vegeta is installed by `go install` to GOPATH/bin, which is normally not in
# PATH on a freshly-installed Go toolchain. Resolve it explicitly.
VEGETA="${VEGETA:-$(command -v vegeta || echo "$HOME/go/bin/vegeta")}"

OUT_DIR="results/${SCENARIO}/vegeta"
mkdir -p "${OUT_DIR}"

echo "[vegeta] sanity check: ${HOST}/healthy"
curl -fsS "${HOST}/healthy" >/dev/null

echo "[vegeta] running: -rate=${RATE} -duration=${DURATION} ${HOST}${ENDPOINT}"
echo "GET ${HOST}${ENDPOINT}" | \
  "${VEGETA}" attack \
    -rate="${RATE}" \
    -duration="${DURATION}" \
    -timeout=5s \
    > "${OUT_DIR}/results.bin"

"${VEGETA}" report -type=text    < "${OUT_DIR}/results.bin" > "${OUT_DIR}/vegeta.txt"
"${VEGETA}" report -type=hdrplot < "${OUT_DIR}/results.bin" > "${OUT_DIR}/vegeta.hdr"
"${VEGETA}" report -type=json    < "${OUT_DIR}/results.bin" > "${OUT_DIR}/vegeta.json"

echo "[vegeta] done — see ${OUT_DIR}/"
