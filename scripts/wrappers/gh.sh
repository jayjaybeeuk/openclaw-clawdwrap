#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source /usr/local/libexec/openclaw-load-runtime-env

load_runtime_env

if [[ -z "${GH_TOKEN:-}" && -n "${GITHUB_TOKEN:-}" ]]; then
  export GH_TOKEN="${GITHUB_TOKEN}"
fi

exec /usr/local/libexec/gh-real "$@"
