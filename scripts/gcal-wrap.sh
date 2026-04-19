#!/usr/bin/env bash
set -euo pipefail

_LIB="/usr/local/libexec/google-auth-lib.sh"
[[ ! -f "$_LIB" ]] && _LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/google-auth-lib.sh"
# shellcheck disable=SC1090
source "$_LIB"; unset _LIB

API_BASE="https://www.googleapis.com/calendar/v3"

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
