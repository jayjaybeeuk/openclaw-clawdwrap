#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/.env"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNC_RUNTIME=0
RESTART_SERVICES=0

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/runtime-volume.sh"

usage() {
  cat <<'EOF'
Refresh GOOGLE_ACCESS_TOKEN using GOOGLE_REFRESH_TOKEN from .env.

Required keys in env file:
  GOOGLE_CLIENT_ID
  GOOGLE_CLIENT_SECRET
  GOOGLE_REFRESH_TOKEN

Usage:
  scripts/refresh-google-token.sh [--env-file .env] [--sync-runtime] [--restart]

Options:
  --env-file <path>  Path to env file (default: .env)
  --sync-runtime     Write runtime secrets to /run/openclaw/env in the detected Docker volume
  --restart          Restart clawwrapd + openclaw-gateway (implies --sync-runtime)
  -h, --help         Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="${2:-}"
      if [[ "$ENV_FILE" != /* && ! "$ENV_FILE" =~ ^[A-Za-z]:[\\/].* ]]; then
        ENV_FILE="$ROOT/$ENV_FILE"
      fi
      shift 2
      ;;
    --sync-runtime)
      SYNC_RUNTIME=1
      shift
      ;;
    --restart)
      SYNC_RUNTIME=1
      RESTART_SERVICES=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Env file not found: $ENV_FILE" >&2
  exit 1
fi

read_env() {
  local key="$1"
  local line
  line="$(grep -m1 "^${key}=" "$ENV_FILE" || true)"
  if [[ -z "$line" ]]; then
    echo ""
  else
    # Handle Windows CRLF and optional quoted values in .env.
    local value="${line#*=}"
    value="${value%$'\r'}"
    if [[ "$value" == \"*\" && "$value" == *\" ]]; then
      value="${value:1:${#value}-2}"
    elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
      value="${value:1:${#value}-2}"
    fi
    echo "$value"
  fi
}

write_env() {
  local key="$1"
  local value="$2"
  local tmp
  tmp="$(mktemp)"
  awk -v k="$key" -v v="$value" '
    BEGIN { done=0 }
    $0 ~ ("^" k "=") { print k "=" v; done=1; next }
    { print }
    END { if (!done) print k "=" v }
  ' "$ENV_FILE" > "$tmp"
  mv "$tmp" "$ENV_FILE"
}

CLIENT_ID="$(read_env GOOGLE_CLIENT_ID)"
CLIENT_SECRET="$(read_env GOOGLE_CLIENT_SECRET)"
REFRESH_TOKEN="$(read_env GOOGLE_REFRESH_TOKEN)"
GITHUB_TOKEN="$(read_env GITHUB_TOKEN)"
ANTHROPIC_API_KEY="$(read_env ANTHROPIC_API_KEY)"
AZURE_DEVOPS_TOKEN="$(read_env AZURE_DEVOPS_TOKEN)"
RUNTIME_VOLUME="$(detect_runtime_volume "$ROOT")"

if [[ -z "$CLIENT_ID" || -z "$CLIENT_SECRET" || -z "$REFRESH_TOKEN" ]]; then
  echo "Missing GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET / GOOGLE_REFRESH_TOKEN in $ENV_FILE" >&2
  exit 1
fi

tmp_body="$(mktemp)"
http_code="$(
  curl -sS -o "$tmp_body" -w "%{http_code}" https://oauth2.googleapis.com/token \
    --data-urlencode "client_id=${CLIENT_ID}" \
    --data-urlencode "client_secret=${CLIENT_SECRET}" \
    --data-urlencode "refresh_token=${REFRESH_TOKEN}" \
    --data-urlencode "grant_type=refresh_token"
)"
response="$(cat "$tmp_body")"
rm -f "$tmp_body"

if [[ "$http_code" != "200" ]]; then
  echo "Token refresh failed (HTTP ${http_code})" >&2
  echo "$response" >&2
  exit 1
fi

ACCESS_TOKEN="$(
  printf '%s' "$response" | node -e '
    let s=""; process.stdin.on("data",d=>s+=d); process.stdin.on("end",()=>{
      const j=JSON.parse(s);
      if (!j.access_token) { process.exit(3); }
      process.stdout.write(j.access_token);
    });
  ' || true
)"

EXPIRES_IN="$(
  printf '%s' "$response" | node -e '
    let s=""; process.stdin.on("data",d=>s+=d); process.stdin.on("end",()=>{
      const j=JSON.parse(s);
      process.stdout.write(String(j.expires_in || ""));
    });
  '
)"

if [[ -z "$ACCESS_TOKEN" ]]; then
  echo "Failed to refresh access token. Raw response:" >&2
  echo "$response" >&2
  exit 1
fi

write_env GOOGLE_ACCESS_TOKEN "$ACCESS_TOKEN"

if [[ -n "$EXPIRES_IN" ]]; then
  write_env GOOGLE_ACCESS_TOKEN_EXPIRES_IN "$EXPIRES_IN"
fi

echo "Updated GOOGLE_ACCESS_TOKEN in $ENV_FILE"

if [[ "$SYNC_RUNTIME" -eq 1 ]]; then
  echo "Syncing runtime secrets to volume ${RUNTIME_VOLUME}"
  docker run --rm \
    -e GH_TOKEN="$GITHUB_TOKEN" \
    -e ANTHROPIC_KEY="$ANTHROPIC_API_KEY" \
    -e AZURE_TOKEN="$AZURE_DEVOPS_TOKEN" \
    -e GOOG_CLIENT_ID="$CLIENT_ID" \
    -e GOOG_CLIENT_SECRET="$CLIENT_SECRET" \
    -e GOOG_REFRESH_TOKEN="$REFRESH_TOKEN" \
    -e GOOG_TOKEN="$ACCESS_TOKEN" \
    -v "${RUNTIME_VOLUME}:/run/openclaw" \
    alpine sh -lc '
      umask 077
      {
        if [ -n "$GH_TOKEN" ]; then echo "GITHUB_TOKEN=$GH_TOKEN"; fi
        if [ -n "$ANTHROPIC_KEY" ]; then echo "ANTHROPIC_API_KEY=$ANTHROPIC_KEY"; fi
        if [ -n "$AZURE_TOKEN" ]; then echo "AZURE_DEVOPS_TOKEN=$AZURE_TOKEN"; fi
        if [ -n "$GOOG_CLIENT_ID" ]; then echo "GOOGLE_CLIENT_ID=$GOOG_CLIENT_ID"; fi
        if [ -n "$GOOG_CLIENT_SECRET" ]; then echo "GOOGLE_CLIENT_SECRET=$GOOG_CLIENT_SECRET"; fi
        if [ -n "$GOOG_REFRESH_TOKEN" ]; then echo "GOOGLE_REFRESH_TOKEN=$GOOG_REFRESH_TOKEN"; fi
        echo "GOOGLE_ACCESS_TOKEN=$GOOG_TOKEN"
      } > /run/openclaw/env
      chown 1000:1000 /run/openclaw/env
      chmod 600 /run/openclaw/env
    '
  echo "Synced /run/openclaw/env in volume ${RUNTIME_VOLUME}"
fi

if [[ "$RESTART_SERVICES" -eq 1 ]]; then
  docker compose --project-directory "$ROOT" restart clawwrapd openclaw-gateway
  echo "Restarted clawwrapd and openclaw-gateway"
fi
