#!/usr/bin/env bash
# Loads E2E_SECRETS_JSON (a JSON object of NAME: value) into GITHUB_ENV and masks every value.
# Shared by the e2e-start-stack action and web-e2e-deployed.yml; Tests/LoadE2eSecrets.Tests.ps1 covers it.
#
# Every value is masked, whatever it looks like: a value alone cannot tell a flag from a secret (a password can be
# "false"). Masking a flag-like value (true/false/yes/no/on/off or one digit) also replaces that text everywhere else
# in the log with ***, so such a value gets a warning naming its key: if the key is not a secret, move it to
# e2e_env_vars.
#
# Callers run it as a child process (bash load-e2e-secrets.sh), which does not inherit the step's error handling, so
# it sets its own: any failed command fails the step rather than reporting secrets as loaded (missing credentials would
# otherwise turn into skipped scenarios instead of a failed setup).
set -euo pipefail

if [ -z "${E2E_SECRETS_JSON:-}" ] || [ "$E2E_SECRETS_JSON" = "{}" ]; then
  echo "ℹ️  No additional E2E secrets JSON to load"
  exit 0
fi

echo "🔐 Loading additional E2E secrets from JSON..."
if ! echo "$E2E_SECRETS_JSON" | jq empty >/dev/null 2>&1; then
  echo "❌ Error: Invalid e2e_secrets JSON syntax"
  exit 1
fi
ROOT_TYPE=$(echo "$E2E_SECRETS_JSON" | jq -r 'type')
if [ "$ROOT_TYPE" != "object" ]; then
  echo "❌ Error: e2e_secrets must be a JSON object of NAME: value pairs (got a JSON $ROOT_TYPE)"
  exit 1
fi

# Write to temp file, mask values, then append to GITHUB_ENV using heredoc (safe for multi-line/special chars)
TEMP_FILE=$(mktemp)
trap 'rm -f "$TEMP_FILE"' EXIT
echo "$E2E_SECRETS_JSON" | jq -r 'to_entries[] | "\(.key)\t\(.value)"' > "$TEMP_FILE"
COUNT=$(wc -l < "$TEMP_FILE")
echo "Loaded secret keys:"
cut -f1 "$TEMP_FILE" | sed 's/^/  - /'
while IFS=$'\t' read -r key value; do
  # Mask secrets: full value first (for single-line), then line-by-line (for multi-line)
  if [[ "$value" != *$'\n'* ]]; then
    echo "::add-mask::$value"
  else
    # ::add-mask:: doesn't handle embedded newlines
    while IFS= read -r line; do
      [ -n "$line" ] && echo "::add-mask::$line"
    done <<< "$value"
  fi
  case "$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')" in
    true|false|yes|no|on|off|[0-9])
      echo "::warning title=Flag-like value in e2e_secrets::${key} has a flag-like value. It is masked like every secret, so that text is replaced with *** throughout the log. If ${key} is not a secret, move it to e2e_env_vars."
      ;;
  esac
  DELIM="EOF_$(openssl rand -hex 8)"
  {
    echo "${key}<<${DELIM}"
    echo "${value}"
    echo "${DELIM}"
  } >> "$GITHUB_ENV"
done < "$TEMP_FILE"
rm -f "$TEMP_FILE"
echo "✅ E2E secrets from JSON loaded and masked ($COUNT variables)"
