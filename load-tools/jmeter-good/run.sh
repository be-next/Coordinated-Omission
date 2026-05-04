#!/usr/bin/env bash
# JMeter GOOD runner — Precise Throughput Timer + 1500 threads.
# Open-loop semantics: the timer schedules 1 000 starts per second
# regardless of response time, the thread pool is sized to absorb the
# slow-down peak. Reports the honest tail.

set -euo pipefail

SCENARIO="${1:-02-single-hiccup}"
HOST="${HOST:-http://127.0.0.1:8080}"

DOMAIN="${HOST#http://}"
DOMAIN="${DOMAIN#https://}"
HOSTNAME="${DOMAIN%:*}"
PORT="${DOMAIN##*:}"
[ "$PORT" = "$DOMAIN" ] && PORT=80

OUT_DIR="results/${SCENARIO}/jmeter-good"
mkdir -p "${OUT_DIR}"
SCRIPT_DIR="$(dirname "$0")"

echo "[jmeter-good] sanity check: ${HOST}/healthy"
curl -fsS "${HOST}/healthy" >/dev/null

echo "[jmeter-good] running open-loop Precise Throughput Timer test plan"
rm -f "${OUT_DIR}/results.jtl"
jmeter -n \
   -t "${SCRIPT_DIR}/plan.jmx" \
   -l "${OUT_DIR}/results.jtl" \
   -j "${OUT_DIR}/jmeter.log" \
   -JHOST="${HOSTNAME}" -JPORT="${PORT}" \
   -Jjmeter.save.saveservice.output_format=csv \
   -Jjmeter.save.saveservice.print_field_names=true \
   > "${OUT_DIR}/jmeter.txt" 2>&1

echo "[jmeter-good] done — see ${OUT_DIR}/"
