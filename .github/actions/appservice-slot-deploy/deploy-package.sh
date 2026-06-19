#!/usr/bin/env bash
set -euo pipefail

RG="${RG:-}"
APP="${APP:-}"
SLOT="${SLOT:-}"
PACKAGE="${PACKAGE:-}"
DEPLOY_TIMEOUT_MINUTES="${DEPLOY_TIMEOUT_MINUTES:-10}"
SCM_SETTLE_SECONDS="${SCM_SETTLE_SECONDS:-45}"

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
case "$SCM_SETTLE_SECONDS" in
  ''|*[!0-9]*) SCM_SETTLE_SECONDS=45 ;;
esac

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
poll_interval_seconds=10
az_timeout_ms=$((timeout_seconds * 1000))
start_log_file="_logs/deploy-${target}-start.log"
kudu_latest_file="_logs/${target}-kudu-latest.json"
kudu_log_file="_logs/${target}-kudu-latest-log.json"
package_size_bytes=$(stat -c%s "$PACKAGE" 2>/dev/null || wc -c < "$PACKAGE" | tr -d ' ')

user=$(az webapp deployment list-publishing-credentials -g "$RG" -n "$APP" "${slot_args[@]}" --query publishingUserName -o tsv 2>"_logs/${target}-publishing-user.err" || true)
pass=$(az webapp deployment list-publishing-credentials -g "$RG" -n "$APP" "${slot_args[@]}" --query publishingPassword -o tsv 2>"_logs/${target}-publishing-password.err" || true)
linux_fx_version=$(az webapp config show -g "$RG" -n "$APP" "${slot_args[@]}" --query linuxFxVersion -o tsv 2>"_logs/${target}-linuxfx.err" || true)
deploy_mode="onedeploy"
if [ -n "$linux_fx_version" ]; then
  deploy_mode="zipdeploy"
fi

if [ -n "$user" ] && [ -n "$pass" ]; then
  echo "::add-mask::$user"
  echo "::add-mask::$pass"
fi

kudu_base="https://${APP}.scm.azurewebsites.net"
if [ -n "$SLOT" ]; then
  kudu_base="https://${APP}-${SLOT}.scm.azurewebsites.net"
fi

previous_deployment_id=""
if [ -n "$user" ] && [ -n "$pass" ]; then
  before_file="_logs/${target}-kudu-before.json"
  if curl -fsS -u "$user:$pass" "$kudu_base/api/deployments/latest" -o "$before_file" 2>"_logs/${target}-kudu-before.err"; then
    if command -v jq >/dev/null 2>&1; then
      previous_deployment_id=$(jq -r '.id // ""' "$before_file")
    else
      previous_deployment_id=$(grep -o '"id":"[^"]*"' "$before_file" | head -n1 | cut -d: -f2 | tr -d '"')
    fi
    if [ -n "$previous_deployment_id" ]; then
      echo "Previous Kudu deployment id: $previous_deployment_id"
    fi
  fi
fi

echo "Starting async package deployment for $PACKAGE to $APP ($target)."
echo "Package size: ${package_size_bytes} bytes. Upload + completion timeout: ${DEPLOY_TIMEOUT_MINUTES}m ..."
echo "Detected App Service runtime: ${linux_fx_version:-<windows/unknown>}; deploy mode: $deploy_mode."
deadline=$((SECONDS + timeout_seconds))
set +e
if [ "$deploy_mode" = "zipdeploy" ]; then
  if [ -z "$user" ] || [ -z "$pass" ]; then
    echo "Linux zipdeploy requires publishing credentials, but none were returned." >"$start_log_file"
    status=1
  else
    {
      echo "Linux App Service detected; clearing run-from-package so Kudu extracts the zip into wwwroot."
      az webapp config appsettings delete -g "$RG" -n "$APP" "${slot_args[@]}" --setting-names WEBSITE_RUN_FROM_PACKAGE --output none || true
      az webapp config appsettings set -g "$RG" -n "$APP" "${slot_args[@]}" --settings SCM_DO_BUILD_DURING_DEPLOYMENT=false --output none
      if [ "$SCM_SETTLE_SECONDS" -gt 0 ]; then
        echo "Waiting ${SCM_SETTLE_SECONDS}s for App Service/SCM configuration changes to settle before zipdeploy."
        sleep "$SCM_SETTLE_SECONDS"
      fi
      echo "Posting package to Kudu zipdeploy endpoint for extraction."
      curl -fsS --connect-timeout 30 --max-time "$timeout_seconds" -u "$user:$pass" -X POST "$kudu_base/api/zipdeploy?isAsync=true" \
        --data-binary @"$PACKAGE" \
        -D "_logs/${target}-zipdeploy-headers.txt"
    } >"$start_log_file" 2>&1
    status=$?
  fi
else
  timeout "${timeout_seconds}s" az webapp deploy \
    --resource-group "$RG" \
    --name "$APP" \
    "${slot_args[@]}" \
    --src-path "$PACKAGE" \
    --type zip \
    --restart true \
    --async true \
    --timeout "$az_timeout_ms" \
    --output json >"$start_log_file" 2>&1
  status=$?
fi
set -e

if [ "$status" -eq 124 ]; then
  echo "Package upload/deployment timed out after ${DEPLOY_TIMEOUT_MINUTES} minutes for $APP ($target)." >&2
  echo "deploy upload-timeout $target" > "$RUNNER_TEMP/deploy_fail.txt"
  tail -n 160 "$start_log_file" || true
  exit 0
elif [ "$status" -ne 0 ]; then
  echo "Package deployment failed for $APP ($target) with exit code $status." >&2
  echo "deploy failed $target" > "$RUNNER_TEMP/deploy_fail.txt"
  tail -n 160 "$start_log_file" || true
  exit 0
fi

echo "Async package deployment accepted for $APP ($target)."
tail -n 80 "$start_log_file" || true

if [ -z "$user" ] || [ -z "$pass" ]; then
  echo "Publishing credentials unavailable; cannot poll Kudu deployment status. Continuing to warm-up checks."
  exit 0
fi

echo "Polling Kudu deployment status at $kudu_base ..."
last_status=""
while [ "$SECONDS" -lt "$deadline" ]; do
  if curl -fsS -u "$user:$pass" "$kudu_base/api/deployments/latest" -o "$kudu_latest_file" 2>"_logs/${target}-kudu-latest.err"; then
    if command -v jq >/dev/null 2>&1; then
      deployment_id=$(jq -r '.id // "<unknown>"' "$kudu_latest_file")
      status_value=$(jq -r '.status // "<unknown>"' "$kudu_latest_file")
      provisioning_state=$(jq -r '.provisioningState // "<unknown>"' "$kudu_latest_file")
      status_text=$(jq -r '.status_text // ""' "$kudu_latest_file")
      complete=$(jq -r '.complete // "<unknown>"' "$kudu_latest_file")
    else
      deployment_id="<jq-unavailable>"
      status_value=$(grep -o '"status":[0-9]*' "$kudu_latest_file" | head -n1 | cut -d: -f2)
      provisioning_state=$(grep -o '"provisioningState":"[^"]*"' "$kudu_latest_file" | head -n1 | cut -d: -f2 | tr -d '"')
      status_text=""
      complete="<unknown>"
    fi

    current="id=${deployment_id} status=${status_value} provisioningState=${provisioning_state} complete=${complete} ${status_text}"
    if [ "$current" != "$last_status" ]; then
      echo "Kudu deployment: $current"
      last_status="$current"
    fi

    if [ -n "$previous_deployment_id" ] && [ "$deployment_id" = "$previous_deployment_id" ]; then
      echo "Waiting for the new deployment to register in Kudu..."
      sleep "$poll_interval_seconds"
      continue
    fi

    if [ "$status_value" = "4" ] || [ "$provisioning_state" = "Succeeded" ]; then
      curl -fsS -u "$user:$pass" "$kudu_base/api/deployments/latest/log" -o "$kudu_log_file" 2>"_logs/${target}-kudu-latest-log.err" || true
      if [ "$deploy_mode" = "zipdeploy" ]; then
        echo "Restarting Linux App Service after extracted zipdeploy so the container reads wwwroot."
        az webapp restart -g "$RG" -n "$APP" "${slot_args[@]}" --output none || true
      fi
      echo "Package deployment completed for $APP ($target)."
      exit 0
    fi

    if [ "$status_value" = "3" ] || [ "$provisioning_state" = "Failed" ]; then
      curl -fsS -u "$user:$pass" "$kudu_base/api/deployments/latest/log" -o "$kudu_log_file" 2>"_logs/${target}-kudu-latest-log.err" || true
      echo "Package deployment failed according to Kudu for $APP ($target)." >&2
      echo "deploy kudu-failed $target" > "$RUNNER_TEMP/deploy_fail.txt"
      exit 0
    fi
  else
    echo "Kudu latest deployment endpoint is not ready yet."
  fi

  sleep "$poll_interval_seconds"
done

curl -fsS -u "$user:$pass" "$kudu_base/api/deployments/latest/log" -o "$kudu_log_file" 2>"_logs/${target}-kudu-latest-log.err" || true
echo "Package deployment did not complete within ${DEPLOY_TIMEOUT_MINUTES} minutes for $APP ($target)." >&2
echo "deploy completion-timeout $target" > "$RUNNER_TEMP/deploy_fail.txt"
exit 0
