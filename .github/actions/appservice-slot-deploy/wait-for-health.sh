#!/usr/bin/env bash
set -euo pipefail

label="${WARMUP_LABEL:-production}"
url="${WARMUP_URL:-}"
minutes="${WARMUP_TIMEOUT_MINUTES:-20}"

if [ -f "$RUNNER_TEMP/deploy_fail.txt" ] || [ -f "$RUNNER_TEMP/warmup_fail.txt" ]; then
  echo "Skipping health check because an earlier deployment phase failed."
  exit 0
fi
if [[ ! "$minutes" =~ ^[1-9][0-9]?$ ]] || [ "$minutes" -gt 60 ] ||
   [[ ! "$label" =~ ^(staging|production|final)$ ]] || [ -z "$url" ]; then
  echo "Invalid health-check URL, label or timeout (expected 1-60 minutes)." >&2
  echo "warmup invalid-inputs" > "$RUNNER_TEMP/warmup_fail.txt"
  exit 0
fi

mkdir -p _logs
body_file="_logs/warmup-${label}-body.txt"
error_file="_logs/warmup-${label}-curl.err"
deadline=$(( $(date +%s) + minutes * 60 ))
attempt=0
echo "Waiting up to ${minutes}m for ${label} HTTP health; no restarts during warm-up."

while true; do
  remaining=$(( deadline - $(date +%s) ))
  if [ "$remaining" -le 0 ]; then break; fi
  request_timeout=15
  if [ "$remaining" -lt "$request_timeout" ]; then request_timeout=$remaining; fi
  connect_timeout=5
  if [ "$request_timeout" -lt "$connect_timeout" ]; then connect_timeout=$request_timeout; fi
  attempt=$((attempt + 1))
  # Read status and body from the same completed response. A second GET can
  # disagree with the first, and an incomplete HTTP 200 is not readiness.
  transport_ok=false
  if code=$(curl -sS --connect-timeout "$connect_timeout" --max-time "$request_timeout" \
      -o "$body_file" -w '%{http_code}' "$url" 2>"$error_file"); then
    transport_ok=true
  fi
  if [[ ! "$code" =~ ^[0-9]{3}$ ]]; then code=000; fi
  if [ "$transport_ok" = true ] && [ "$code" = 200 ] &&
     ! grep -qi 'iisnode encountered an error' "$body_file"; then
    echo "${label} ready (HTTP 200, attempt ${attempt})."
    exit 0
  fi
  echo "${label} not ready (attempt ${attempt}, HTTP ${code}, transport_ok=${transport_ok})."
  remaining=$(( deadline - $(date +%s) ))
  if [ "$remaining" -le 0 ]; then break; fi
  delay=5
  if [ "$remaining" -lt "$delay" ]; then delay=$remaining; fi
  sleep "$delay"
done

echo "${label} failed HTTP readiness after ${minutes}m; last response saved in ${body_file}." >&2
echo "$label health-timeout" > "$RUNNER_TEMP/warmup_fail.txt"
# Preserve the existing composite contract: collect diagnostics, then fail.
exit 0
