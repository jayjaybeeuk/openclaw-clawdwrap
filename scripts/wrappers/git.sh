#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source /usr/local/libexec/openclaw-load-runtime-env

load_runtime_env

if [[ -z "${GH_TOKEN:-}" && -n "${GITHUB_TOKEN:-}" ]]; then
  export GH_TOKEN="${GITHUB_TOKEN}"
fi

export GIT_ASKPASS="${GIT_ASKPASS:-/usr/local/bin/git-askpass-runtime}"
export GIT_TERMINAL_PROMPT=0

exec /usr/local/libexec/git-real "$@"
