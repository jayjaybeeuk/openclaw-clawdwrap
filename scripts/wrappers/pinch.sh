#!/usr/bin/env bash
set -euo pipefail

: "${PINCHTAB_URL:=http://pinchtab:9867}"
export PINCHTAB_URL

if [[ -n "${PINCHTAB_TOKEN:-}" ]]; then
  export PINCHTAB_TOKEN
fi

exec /usr/local/bin/pinchtab "$@"
