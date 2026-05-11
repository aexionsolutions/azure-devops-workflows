#!/usr/bin/env bash
set -euo pipefail

RG="${RG:-}"
APP="${APP:-}"
SLOT="${SLOT:-}"
PACKAGE="${PACKAGE:-}"
DEPLOY_TIMEOUT_MINUTES="${DEPLOY_TIMEOUT_MINUTES:-10}"

if [ -z "$RG" ] || [ -z "$APP" ] || [ -z "$PACKAGE" ]; then
  echo "Missing RG/APP/PACKAGE environment variables" >&2
  echo "deploy missing-inputs" > "$RUNNER_TEMP/deploy_fail.txt"
  exit 0
fi

case "$DEPLOY_TIMEOUT_MINUTES" in
  ''|*[!0-9]*) DEPLOY_TIMEOUT_MINUTES=10 ;;
esac
if [ "$DEPLOY_TIMEOUT_MINUTES" -lt 1 ]; then
  DEPLOY_TIMEOUT_MINUTES=1
fi

if [ ! -f "$PACKAGE" ]; then
  echo "Package not found: $PACKAGE" >&2
  echo "deploy package-not-found" > "$RUNNER_TEMP/deploy_fail.txt"
  exit 0
fi

target="production"
slot_args=()
if [ -n "$SLOT" ]; then
  target="slot-$SLOT"
  slot_args=(--slot "$SLOT")
fi

mkdir -p _logs
timeout_seconds=$((DEPLOY_TIMEOUT_MINUTES * 60))
az_timeout_seconds=$timeout_seconds
if [ "$timeout_seconds" -gt 45 ]; then
  az_timeout_seconds=$((timeout_seconds - 15))
fi
az_timeout_ms=$((az_timeout_seconds * 1000))
log_file="_logs/deploy-${target}.log"

echo "Deploying $PACKAGE to $APP ($target). Timeout: ${DEPLOY_TIMEOUT_MINUTES}m ..."
set +e
timeout "${timeout_seconds}s" az webapp deploy \
  --resource-group "$RG" \
  --name "$APP" \
  "${slot_args[@]}" \
  --src-path "$PACKAGE" \
  --type zip \
  --restart true \
  --timeout "$az_timeout_ms" \
  --output json >"$log_file" 2>&1
status=$?
set -e

if [ "$status" -eq 0 ]; then
  echo "Package deployment completed for $APP ($target)."
  tail -n 80 "$log_file" || true
  exit 0
fi

if [ "$status" -eq 124 ]; then
  echo "Package deployment timed out after ${DEPLOY_TIMEOUT_MINUTES} minutes for $APP ($target)." >&2
  echo "deploy timeout $target" > "$RUNNER_TEMP/deploy_fail.txt"
else
  echo "Package deployment failed for $APP ($target) with exit code $status." >&2
  echo "deploy failed $target" > "$RUNNER_TEMP/deploy_fail.txt"
fi

tail -n 160 "$log_file" || true
exit 0
