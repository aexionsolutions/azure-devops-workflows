#!/usr/bin/env bash
set -euo pipefail

RG="${RG:-}"
APP="${APP:-}"
SLOT="${SLOT:-}"

if [ -z "${RG}" ] || [ -z "${APP}" ]; then
  echo "Missing RG/APP environment variables" >&2
  exit 1
fi

if [ -n "${SLOT}" ]; then
  echo "Starting slot ${SLOT} for ${APP}..."
  az webapp start -g "$RG" -n "$APP" --slot "$SLOT" >/dev/null 2>&1 || true
  for i in {1..30}; do
    state=$(az webapp show -g "$RG" -n "$APP" --slot "$SLOT" --query state -o tsv 2>/dev/null || echo "Unknown")
    echo "State(${SLOT}): $state"
    if [ "$state" = "Running" ]; then exit 0; fi
    sleep 2
  done
  echo "Slot $SLOT did not report Running within timeout" >&2
  exit 1
fi

echo "Starting production app ${APP}..."
az webapp start -g "$RG" -n "$APP" >/dev/null 2>&1 || true
for i in {1..30}; do
  state=$(az webapp show -g "$RG" -n "$APP" --query state -o tsv 2>/dev/null || echo "Unknown")
  echo "State(prod): $state"
  if [ "$state" = "Running" ]; then exit 0; fi
  sleep 2
 done

echo "App did not report Running within timeout" >&2
exit 1
