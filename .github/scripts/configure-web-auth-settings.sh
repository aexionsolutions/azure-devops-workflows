#!/usr/bin/env bash
set -euo pipefail

AUTHORITY="${B2C_AUTHORITY:-}"
CLIENT_ID="${B2C_WEB_CLIENT_ID:-${B2C_CLIENT_ID:-}}"
API_SCOPE="${B2C_SCOPE:-}"
USE_SLOT="${USE_SLOT:-false}"

if [ -z "$AUTHORITY" ] && [ -z "$CLIENT_ID" ] && [ -z "$API_SCOPE" ]; then
  echo "No B2C web auth settings supplied; leaving existing App Service settings unchanged."
  exit 0
fi

missing=()
[ -n "$AUTHORITY" ] || missing+=("b2c_authority")
[ -n "$CLIENT_ID" ] || missing+=("b2c_web_client_id or b2c_client_id")
[ -n "$API_SCOPE" ] || missing+=("b2c_scope")

if [ "${#missing[@]}" -gt 0 ]; then
  printf 'Incomplete B2C web auth configuration. Missing: %s\n' "${missing[*]}" >&2
  exit 1
fi

set_auth_settings() {
  local slot_arg=()
  local host="$APP.azurewebsites.net"
  local target="production"

  if [ "${1:-}" = "staging" ]; then
    slot_arg=(--slot staging)
    host="$APP-staging.azurewebsites.net"
    target="staging"
  fi

  local redirect_uri="https://${host}/auth/callback"
  local settings=(
    "AAD_AUTHORITY=$AUTHORITY"
    "NEXT_PUBLIC_AAD_AUTHORITY=$AUTHORITY"
    "AAD_CLIENT_ID=$CLIENT_ID"
    "NEXT_PUBLIC_AAD_CLIENT_ID=$CLIENT_ID"
    "AAD_API_SCOPE=$API_SCOPE"
    "NEXT_PUBLIC_AAD_API_SCOPE=$API_SCOPE"
    "AAD_REDIRECT_URI=$redirect_uri"
    "NEXT_PUBLIC_AAD_REDIRECT_URI=$redirect_uri"
    "AAD_B2C_AUTHORITY=$AUTHORITY"
    "NEXT_PUBLIC_AAD_B2C_AUTHORITY=$AUTHORITY"
    "AAD_B2C_CLIENT_ID=$CLIENT_ID"
    "NEXT_PUBLIC_AAD_B2C_CLIENT_ID=$CLIENT_ID"
    "AAD_B2C_API_SCOPE=$API_SCOPE"
    "NEXT_PUBLIC_AAD_B2C_API_SCOPE=$API_SCOPE"
    "AAD_B2C_REDIRECT_URI=$redirect_uri"
    "NEXT_PUBLIC_AAD_B2C_REDIRECT_URI=$redirect_uri"
  )

  echo "Applying B2C web auth app settings to $APP ($target)..."
  az webapp config appsettings set -g "$RG" -n "$APP" "${slot_arg[@]}" --settings "${settings[@]}" >/dev/null
}

if [ "$USE_SLOT" = "true" ]; then
  set_auth_settings staging
  set_auth_settings production
else
  set_auth_settings production
fi
