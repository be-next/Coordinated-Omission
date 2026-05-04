#!/usr/bin/env bash
# k6 BAD runner — constant-vus executor (closed loop).

set -euo pipefail

SCENARIO="${1:-02-single-hiccup}"
HOST="${HOST:-http://127.0.0.1:8080}"

OUT_DIR="results/${SCENARIO}/k6-bad"
mkdir -p "${OUT_DIR}"

echo "[k6-bad] sanity check: ${HOST}/healthy"
curl -fsS "${HOST}/healthy" >/dev/null

SCRIPT_DIR="$(dirname "$0")"

echo "[k6-bad] running constant-vus closed-loop scenario"
HOST="${HOST}" k6 run \
   --quiet \
   --summary-trend-stats="min,med,avg,p(50),p(75),p(90),p(95),p(99),p(99.5),p(99.9),p(99.99),max" \
   --summary-export="${OUT_DIR}/summary.json" \
   --out csv="${OUT_DIR}/samples.csv" \
   "${SCRIPT_DIR}/script.js" \
   > "${OUT_DIR}/k6.txt" 2>&1

echo "[k6-bad] done — see ${OUT_DIR}/"
