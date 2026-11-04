#!/usr/bin/env bash
set -euo pipefail

clean_node_runtime() {
  local root="$1"
  case "$root" in /*/site/wwwroot) ;; *) echo 'Unexpected application root; refusing cleanup.' >&2; return 1 ;; esac
  if [ "$(pwd -P)" != "$root" ] || [ -L "$root" ] ||
     [ -L .next ] || [ -L .next/cache ]; then
    echo 'Unexpected application root or cache symlink; refusing cleanup.' >&2
    return 1
  fi
  if [ -e .next/cache ] && [ ! -d .next/cache ]; then
    echo 'Unexpected Next cache type; refusing cleanup.' >&2
    return 1
  fi
  if [ -d .next/cache ] && [ "$(realpath .next/cache)" != "$root/.next/cache" ]; then
    echo 'Next cache is outside the application root; refusing cleanup.' >&2
    return 1
  fi

  # These are generated build/runtime artifacts, not application uploads. Old
  # Oryx archives otherwise replace freshly deployed node_modules at startup.
  for artifact in oryx-manifest.toml node_modules.tar.zst node_modules.tar.gz node_modules.tar; do
    if [ -e "$artifact" ] || [ -L "$artifact" ]; then echo "Removing generated artifact: $artifact"; fi
    rm -f -- "$artifact"
  done
  if [ -L node_modules ]; then rm -- node_modules; fi
  if [ -d .next/cache ]; then rm -rf -- .next/cache; fi
  echo 'Removed generated Next cache and legacy Oryx runtime artifacts.'
  echo 'APP_SERVICE_NODE_CLEANUP_COMPLETE'
}

# Kudu pipes the decoded script into Bash, where BASH_SOURCE has no element.
# A sourced file still has its own source path and must only define the function.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  clean_node_runtime /home/site/wwwroot
fi
