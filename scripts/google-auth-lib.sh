#!/usr/bin/env bash
# google-auth-lib.sh — shared Google OAuth helpers.
# Source this file; do not execute it directly.

_GAUTH_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_GAUTH_RUNTIME_HELPER="/usr/local/libexec/openclaw-load-runtime-env"

if [[ ! -f "$_GAUTH_RUNTIME_HELPER" ]]; then
  _GAUTH_RUNTIME_HELPER="${_GAUTH_LIB_DIR}/load-runtime-env.sh"
fi

# shellcheck disable=SC1090
source "$_GAUTH_RUNTIME_HELPER"
load_runtime_env /run/openclaw/env

unset _GAUTH_LIB_DIR _GAUTH_RUNTIME_HELPER

require_oauth() {
  if [[ -z "${GOOGLE_CLIENT_ID:-}" || -z "${GOOGLE_CLIENT_SECRET:-}" || -z "${GOOGLE_REFRESH_TOKEN:-}" ]]; then
    echo "GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET and GOOGLE_REFRESH_TOKEN are required" >&2
    exit 2
  fi
}

mint_access_token() {
  local response token
  response="$(
    curl -fsS https://oauth2.googleapis.com/token \
      --data-urlencode "client_id=${GOOGLE_CLIENT_ID}" \
      --data-urlencode "client_secret=${GOOGLE_CLIENT_SECRET}" \
      --data-urlencode "refresh_token=${GOOGLE_REFRESH_TOKEN}" \
      --data-urlencode "grant_type=refresh_token"
  )"
  token="$(
    printf '%s' "$response" | node -e '
      let s=""; process.stdin.on("data",d=>s+=d); process.stdin.on("end",()=>{
        const j=JSON.parse(s);
        if (!j.access_token) process.exit(3);
        process.stdout.write(j.access_token);
      });
    ' || true
  )"
  if [[ -z "$token" ]]; then
    echo "Failed to mint Google access token" >&2
    exit 1
  fi
  GOOGLE_ACCESS_TOKEN="$token"
}
