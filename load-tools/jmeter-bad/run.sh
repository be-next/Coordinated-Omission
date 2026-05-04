#!/usr/bin/env bash
# JMeter BAD runner — default ThreadGroup, no throughput shaping.
# 10 threads loop forever for 60 s; the moment the server stalls, all
# 10 threads stall with it. Closed loop, susceptible to coordinated omission.

set -euo pipefail

SCENARIO="${1:-02-single-hiccup}"
HOST="${HOST:-http://127.0.0.1:8080}"

# Strip protocol from HOST, JMeter expects domain + port separately.
DOMAIN="${HOST#http://}"
DOMAIN="${DOMAIN#https://}"
HOSTNAME="${DOMAIN%:*}"
PORT="${DOMAIN##*:}"
[ "$PORT" = "$DOMAIN" ] && PORT=80

OUT_DIR="results/${SCENARIO}/jmeter-bad"
mkdir -p "${OUT_DIR}"
SCRIPT_DIR="$(dirname "$0")"

echo "[jmeter-bad] sanity check: ${HOST}/healthy"
curl -fsS "${HOST}/healthy" >/dev/null

echo "[jmeter-bad] running closed-loop ThreadGroup test plan"
rm -f "${OUT_DIR}/results.jtl"
jmeter -n \
   -t "${SCRIPT_DIR}/plan.jmx" \
   -l "${OUT_DIR}/results.jtl" \
   -j "${OUT_DIR}/jmeter.log" \
   -JHOST="${HOSTNAME}" -JPORT="${PORT}" \
   -Jjmeter.save.saveservice.output_format=csv \
   -Jjmeter.save.saveservice.print_field_names=true \
   > "${OUT_DIR}/jmeter.txt" 2>&1

echo "[jmeter-bad] done — see ${OUT_DIR}/"
