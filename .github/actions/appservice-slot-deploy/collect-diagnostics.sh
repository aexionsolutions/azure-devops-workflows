#!/usr/bin/env bash
set -euo pipefail

RG="${RG:-}"
APP="${APP:-}"
USE_SLOT="${USE_SLOT:-false}"

if [ ! -f "$RUNNER_TEMP/deploy_fail.txt" ] && [ ! -f "$RUNNER_TEMP/warmup_fail.txt" ]; then
  exit 0
fi

if [ -z "$RG" ] || [ -z "$APP" ]; then
  echo "Missing RG/APP environment variables; cannot collect App Service diagnostics." >&2
  exit 0
fi

mkdir -p _logs
echo "Collecting App Service diagnostics for $APP..."

az webapp show -g "$RG" -n "$APP" \
  --query "{name:name,state:state,availabilityState:availabilityState,enabled:enabled,defaultHostName:defaultHostName,lastModifiedTimeUtc:lastModifiedTimeUtc}" \
  -o json > _logs/prod-app-state.json 2>_logs/prod-app-state.err || true

az webapp config appsettings list -g "$RG" -n "$APP" \
  --query "[?name=='WEBSITE_RUN_FROM_PACKAGE' || name=='BUILD_VERSION' || name=='ENV' || name=='ASPNETCORE_ENVIRONMENT' || name=='DOTNET_ENVIRONMENT' || name=='SCM_DO_BUILD_DURING_DEPLOYMENT' || name=='WEBSITE_ENABLE_SYNC_UPDATE_SITE'].{name:name,value:value,slotSetting:slotSetting}" \
  -o json > _logs/prod-deploy-settings.json 2>_logs/prod-deploy-settings.err || true

timeout 180s az webapp log download -g "$RG" -n "$APP" --log-file _logs/prod_logs.zip 2>_logs/prod-log-download.err || true

if [ "$USE_SLOT" = "true" ]; then
  az webapp show -g "$RG" -n "$APP" --slot staging \
    --query "{name:name,state:state,availabilityState:availabilityState,enabled:enabled,defaultHostName:defaultHostName,lastModifiedTimeUtc:lastModifiedTimeUtc}" \
    -o json > _logs/staging-app-state.json 2>_logs/staging-app-state.err || true

  az webapp config appsettings list -g "$RG" -n "$APP" --slot staging \
    --query "[?name=='WEBSITE_RUN_FROM_PACKAGE' || name=='BUILD_VERSION' || name=='ENV' || name=='ASPNETCORE_ENVIRONMENT' || name=='DOTNET_ENVIRONMENT' || name=='SCM_DO_BUILD_DURING_DEPLOYMENT' || name=='WEBSITE_ENABLE_SYNC_UPDATE_SITE'].{name:name,value:value,slotSetting:slotSetting}" \
    -o json > _logs/staging-deploy-settings.json 2>_logs/staging-deploy-settings.err || true

  timeout 180s az webapp log download -g "$RG" -n "$APP" --slot staging --log-file _logs/staging_logs.zip 2>_logs/staging-log-download.err || true
fi

user=$(az webapp deployment list-publishing-credentials -g "$RG" -n "$APP" --query publishingUserName -o tsv 2>/dev/null || true)
pass=$(az webapp deployment list-publishing-credentials -g "$RG" -n "$APP" --query publishingPassword -o tsv 2>/dev/null || true)

if [ -n "$user" ] && [ -n "$pass" ]; then
  echo "::add-mask::$user"
  echo "::add-mask::$pass"

  prod_base="https://${APP}.scm.azurewebsites.net"
  curl -fsS -u "$user:$pass" "$prod_base/api/deployments/latest" -o _logs/prod-kudu-latest.json 2>_logs/prod-kudu-latest.err || true
  curl -fsS -u "$user:$pass" "$prod_base/api/deployments/latest/log" -o _logs/prod-kudu-latest-log.json 2>_logs/prod-kudu-latest-log.err || true

  if [ "$USE_SLOT" = "true" ]; then
    staging_user=$(az webapp deployment list-publishing-credentials -g "$RG" -n "$APP" --slot staging --query publishingUserName -o tsv 2>/dev/null || true)
    staging_pass=$(az webapp deployment list-publishing-credentials -g "$RG" -n "$APP" --slot staging --query publishingPassword -o tsv 2>/dev/null || true)
    if [ -n "$staging_user" ] && [ -n "$staging_pass" ]; then
      echo "::add-mask::$staging_user"
      echo "::add-mask::$staging_pass"
    else
      staging_user="$user"
      staging_pass="$pass"
    fi

    staging_base="https://${APP}-staging.scm.azurewebsites.net"
    curl -fsS -u "$staging_user:$staging_pass" "$staging_base/api/deployments/latest" -o _logs/staging-kudu-latest.json 2>_logs/staging-kudu-latest.err || true
    curl -fsS -u "$staging_user:$staging_pass" "$staging_base/api/deployments/latest/log" -o _logs/staging-kudu-latest-log.json 2>_logs/staging-kudu-latest-log.err || true
  fi
else
  echo "Publishing credentials unavailable; skipping Kudu diagnostic endpoints." > _logs/kudu-credentials-unavailable.txt
fi
