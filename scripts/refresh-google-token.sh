#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=".env"
RUNTIME_VOLUME="openclaw-docker-stack_openclaw_run"
SYNC_RUNTIME=0
RESTART_SERVICES=0

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
  --sync-runtime     Write GITHUB_TOKEN + GOOGLE_ACCESS_TOKEN to /run/openclaw/env volume
  --restart          Restart clawwrapd + openclaw-gateway (implies --sync-runtime)
  -h, --help         Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env-file)
      ENV_FILE="${2:-}"
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
  docker run --rm \
    -e GH_TOKEN="$GITHUB_TOKEN" \
    -e GOOG_TOKEN="$ACCESS_TOKEN" \
    -v "${RUNTIME_VOLUME}:/run/openclaw" \
    alpine sh -lc '
      umask 077
      {
        if [ -n "$GH_TOKEN" ]; then echo "GITHUB_TOKEN=$GH_TOKEN"; fi
        echo "GOOGLE_ACCESS_TOKEN=$GOOG_TOKEN"
      } > /run/openclaw/env
      chown 1000:1000 /run/openclaw/env
      chmod 600 /run/openclaw/env
    '
  echo "Synced /run/openclaw/env in volume ${RUNTIME_VOLUME}"
fi

if [[ "$RESTART_SERVICES" -eq 1 ]]; then
  docker compose restart clawwrapd openclaw-gateway
  echo "Restarted clawwrapd and openclaw-gateway"
fi
