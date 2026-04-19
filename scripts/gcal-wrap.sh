#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ENV_HELPER="/usr/local/libexec/openclaw-load-runtime-env"

if [[ ! -f "$RUNTIME_ENV_HELPER" ]]; then
  RUNTIME_ENV_HELPER="${SCRIPT_DIR}/load-runtime-env.sh"
fi

# shellcheck disable=SC1090
source "$RUNTIME_ENV_HELPER"
load_runtime_env /run/openclaw/env

API_BASE="https://www.googleapis.com/calendar/v3"

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

usage() {
  cat <<'EOF'
Usage:
  gcal-wrap list-calendars
  gcal-wrap create-event --summary TEXT --start RFC3339 --end RFC3339 [--calendar ID] [--timezone TZ] [--description TEXT] [--location TEXT]
EOF
}

create_event() {
  local calendar="primary"
  local summary="" start="" end="" timezone=""
  local description="" location=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --calendar) calendar="${2:-}"; shift 2 ;;
      --summary) summary="${2:-}"; shift 2 ;;
      --start) start="${2:-}"; shift 2 ;;
      --end) end="${2:-}"; shift 2 ;;
      --timezone) timezone="${2:-}"; shift 2 ;;
      --description) description="${2:-}"; shift 2 ;;
      --location) location="${2:-}"; shift 2 ;;
      *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
    esac
  done

  if [[ -z "$summary" || -z "$start" || -z "$end" ]]; then
    echo "Missing required args: --summary, --start, --end" >&2
    usage
    exit 2
  fi

  local payload
  payload="$(
    SUMMARY="$summary" START="$start" END="$end" TZ="$timezone" DESC="$description" LOC="$location" \
      node -e "const o={summary:process.env.SUMMARY,start:{dateTime:process.env.START},end:{dateTime:process.env.END}};if(process.env.TZ){o.start.timeZone=process.env.TZ;o.end.timeZone=process.env.TZ;}if(process.env.DESC){o.description=process.env.DESC;}if(process.env.LOC){o.location=process.env.LOC;}process.stdout.write(JSON.stringify(o));"
  )"

  curl -fsS \
    -H "Authorization: Bearer ${GOOGLE_ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -X POST \
    -d "$payload" \
    "${API_BASE}/calendars/${calendar}/events"
}

main() {
  require_oauth
  mint_access_token
  local cmd="${1:-}"
  case "$cmd" in
    list-calendars)
      shift
      curl -fsS \
        -H "Authorization: Bearer ${GOOGLE_ACCESS_TOKEN}" \
        "${API_BASE}/users/me/calendarList"
      ;;
    create-event)
      shift
      create_event "$@"
      ;;
    *)
      usage
      exit 2
      ;;
  esac
}

main "$@"
