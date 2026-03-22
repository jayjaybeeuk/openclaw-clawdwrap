#!/usr/bin/env bash
set -euo pipefail

API_BASE="https://gmail.googleapis.com/gmail/v1/users/me/messages"

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
