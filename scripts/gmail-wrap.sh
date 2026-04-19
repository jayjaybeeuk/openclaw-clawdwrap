#!/usr/bin/env bash
set -euo pipefail

_LIB="/usr/local/libexec/google-auth-lib.sh"
[[ ! -f "$_LIB" ]] && _LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/google-auth-lib.sh"
# shellcheck disable=SC1090
source "$_LIB"; unset _LIB

API_BASE="https://gmail.googleapis.com/gmail/v1/users/me/messages"

usage() {
  cat <<'EOF'
Usage:
  gmail-wrap send --to EMAIL --subject TEXT --body TEXT [--cc EMAILS] [--from EMAIL]
EOF
}

send_mail() {
  local to="" subject="" body="" cc="" from=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --to) to="${2:-}"; shift 2 ;;
      --subject) subject="${2:-}"; shift 2 ;;
      --body) body="${2:-}"; shift 2 ;;
      --cc) cc="${2:-}"; shift 2 ;;
      --from) from="${2:-}"; shift 2 ;;
      *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
    esac
  done

  if [[ -z "$to" || -z "$subject" || -z "$body" ]]; then
    echo "Missing required args: --to, --subject, --body" >&2
    usage
    exit 2
  fi

  local raw="To: ${to}
Subject: ${subject}
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8"

  if [[ -n "$cc" ]]; then
    raw="${raw}
Cc: ${cc}"
  fi

  if [[ -n "$from" ]]; then
    raw="${raw}
From: ${from}"
  fi

  raw="${raw}

${body}
"

  local raw_b64 payload
  raw_b64="$(node -e "process.stdout.write(Buffer.from(process.argv[1],'utf8').toString('base64url'))" "$raw")"
  payload="$(node -e "process.stdout.write(JSON.stringify({raw:process.argv[1]}))" "$raw_b64")"

  curl -fsS \
    -H "Authorization: Bearer ${GOOGLE_ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -X POST \
    -d "$payload" \
    "${API_BASE}/send"
}

main() {
  require_oauth
  mint_access_token
  local cmd="${1:-}"
  case "$cmd" in
    send)
      shift
      send_mail "$@"
      ;;
    *)
      usage
      exit 2
      ;;
  esac
}

main "$@"
