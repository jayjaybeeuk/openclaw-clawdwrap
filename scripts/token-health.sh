#!/usr/bin/env bash
# scripts/token-health.sh — Check auth/token health for GitHub, Google, and LLM providers.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/.env"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
YEL='\033[0;33m'
GRN='\033[0;32m'
BLD='\033[1m'
RST='\033[0m'

ok()   { printf "  ${GRN}✓${RST} %s\n" "$*"; }
warn() { printf "  ${YEL}!${RST} %s\n" "$*"; }
err()  { printf "  ${RED}✗${RST} %s\n" "$*"; }

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/runtime-volume.sh"

FAILED=0
WARNED=0

get_raw() {
  grep -E "^${1}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d'=' -f2- | sed 's/#.*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed "s/\r$//" || true
}

trim_quotes() {
  local value="$1"
  if [[ "$value" == \"*\" && "$value" == *\" ]]; then
    value="${value:1:${#value}-2}"
  elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
    value="${value:1:${#value}-2}"
  fi
  printf '%s' "$value"
}

has_value() {
  local value
  value="$(trim_quotes "${1:-}")"
  [[ -n "$value" ]]
}

runtime_env_has() {
  local key="$1"
  local volume="$2"
  docker run --rm -v "${volume}:/run/openclaw" alpine sh -lc "grep -q '^${key}=' /run/openclaw/env" >/dev/null 2>&1
}

gateway_running() {
  docker compose --project-directory "$ROOT" ps --status running --services 2>/dev/null | grep -qx "openclaw-gateway"
}

read_auth_profiles_status() {
  local config_dir auth_file
  config_dir="$(trim_quotes "$(get_raw OPENCLAW_CONFIG_DIR)")"
  [[ -z "$config_dir" ]] && return 1
  auth_file="${config_dir}/agents/main/agent/auth-profiles.json"
  [[ ! -f "$auth_file" ]] && return 1
  node -e "
    try {
      const p = JSON.parse(require('fs').readFileSync(process.argv[1], 'utf8')).profiles || {};
      const values = Object.values(p);
      const hasOauth = values.some(v => v.mode === 'oauth' || v.type === 'oauth' || v.type === 'token');
      const hasApiKey = values.some(v => v.type === 'api_key');
      process.stdout.write(hasOauth ? 'oauth' : (hasApiKey ? 'api_key' : 'unknown'));
    } catch (_) { process.exit(1); }
  " "$auth_file" 2>/dev/null
}

printf "\n${BLD}Token Health Check${RST}\n"

if [[ ! -f "$ENV_FILE" ]]; then
  err ".env not found — run ./setup.sh first"
  exit 1
fi

printf "\n${BLD}Config${RST}\n"

github_token="$(trim_quotes "$(get_raw GITHUB_TOKEN)")"
if has_value "$github_token"; then
  ok "GITHUB_TOKEN present in .env"
else
  err "GITHUB_TOKEN missing in .env — GitHub calls will fail"
  FAILED=$((FAILED + 1))
fi

google_client_id="$(trim_quotes "$(get_raw GOOGLE_CLIENT_ID)")"
google_client_secret="$(trim_quotes "$(get_raw GOOGLE_CLIENT_SECRET)")"
google_refresh_token="$(trim_quotes "$(get_raw GOOGLE_REFRESH_TOKEN)")"
if has_value "$google_client_id" && has_value "$google_client_secret" && has_value "$google_refresh_token"; then
  ok "Google OAuth client + refresh token present in .env"
elif has_value "$google_client_id" || has_value "$google_client_secret" || has_value "$google_refresh_token"; then
  warn "Google OAuth config is partial — update GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET / GOOGLE_REFRESH_TOKEN"
  WARNED=$((WARNED + 1))
else
  warn "Google OAuth config not set — gcal/gmail will not work"
  WARNED=$((WARNED + 1))
fi

llm_auth_mode="$(trim_quotes "$(get_raw LLM_AUTH_MODE)")"
llm_auth_mode="${llm_auth_mode:-api_key}"
if [[ "$llm_auth_mode" == "oauth" ]]; then
  case "$(read_auth_profiles_status 2>/dev/null || true)" in
    oauth)
      ok "LLM_AUTH_MODE=oauth and OAuth profiles exist"
      ;;
    api_key)
      warn "LLM_AUTH_MODE=oauth but only API-key profiles were found — run make login"
      WARNED=$((WARNED + 1))
      ;;
    *)
      warn "LLM_AUTH_MODE=oauth but no OAuth profiles were found — run make login"
      WARNED=$((WARNED + 1))
      ;;
  esac
else
  openai_key="$(trim_quotes "$(get_raw OPENAI_API_KEY)")"
  anthropic_key="$(trim_quotes "$(get_raw ANTHROPIC_API_KEY)")"
  if has_value "$openai_key" || has_value "$anthropic_key"; then
    ok "LLM_AUTH_MODE=api_key and at least one provider key is present"
  else
    err "LLM_AUTH_MODE=api_key but no OPENAI_API_KEY or ANTHROPIC_API_KEY is set"
    FAILED=$((FAILED + 1))
  fi
fi

printf "\n${BLD}Runtime Volume${RST}\n"

if docker info >/dev/null 2>&1; then
  runtime_volume="$(detect_runtime_volume "$ROOT")"
  if docker volume inspect "$runtime_volume" >/dev/null 2>&1; then
    ok "Runtime volume exists: $runtime_volume"
    if runtime_env_has GITHUB_TOKEN "$runtime_volume"; then
      ok "Runtime env contains GITHUB_TOKEN"
    else
      warn "Runtime env is missing GITHUB_TOKEN — run make inject-tokens or scripts/inject-tokens.ps1"
      WARNED=$((WARNED + 1))
    fi
    if has_value "$google_refresh_token"; then
      if runtime_env_has GOOGLE_REFRESH_TOKEN "$runtime_volume"; then
        ok "Runtime env contains Google OAuth credentials"
      else
        warn "Runtime env is missing Google OAuth credentials — re-run token injection"
        WARNED=$((WARNED + 1))
      fi
    fi
  else
    warn "Runtime volume not found yet ($runtime_volume) — start the stack first"
    WARNED=$((WARNED + 1))
  fi
else
  warn "Docker is not available — skipping runtime checks"
  WARNED=$((WARNED + 1))
fi

printf "\n${BLD}Live Checks${RST}\n"

if gateway_running; then
  gh_login="$(docker compose --project-directory "$ROOT" exec -T openclaw-gateway sh -lc "gh api user --jq '.login'" 2>/dev/null || true)"
  if [[ -n "$gh_login" ]]; then
    ok "GitHub auth works in gateway as ${gh_login}"
  else
    warn "GitHub live check failed — verify GITHUB_TOKEN and runtime injection"
    WARNED=$((WARNED + 1))
  fi

  if has_value "$google_refresh_token"; then
    if docker compose --project-directory "$ROOT" exec -T openclaw-gateway sh -lc "gcal list-calendars >/dev/null 2>&1" >/dev/null 2>&1; then
      ok "Google Calendar auth works in gateway"
    else
      warn "Google live check failed — re-auth Google and run refresh-google-token"
      WARNED=$((WARNED + 1))
    fi
  else
    warn "Skipping Google live check because GOOGLE_REFRESH_TOKEN is not configured"
    WARNED=$((WARNED + 1))
  fi
else
  warn "openclaw-gateway is not running — skipping live checks"
  WARNED=$((WARNED + 1))
fi

printf "\n${BLD}Next Steps${RST}\n"
printf "  - GitHub broken: update GITHUB_TOKEN, then run make inject-tokens or .\\scripts\\inject-tokens.ps1\n"
printf "  - Google broken: replace GOOGLE_REFRESH_TOKEN, then run refresh-google-token with restart\n"
printf "  - LLM OAuth missing: run make login\n"

printf "\n"
if [[ "$FAILED" -gt 0 ]]; then
  printf "${RED}${BLD}Token health failed: %d blocking issue(s), %d warning(s).${RST}\n\n" "$FAILED" "$WARNED"
  exit 1
fi

if [[ "$WARNED" -gt 0 ]]; then
  printf "${YEL}${BLD}Token health completed with %d warning(s).${RST}\n\n" "$WARNED"
  exit 0
fi

printf "${GRN}${BLD}Token health passed.${RST}\n\n"
