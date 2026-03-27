#!/usr/bin/env bash
# scripts/preflight.sh — Pre-flight check run before docker compose up.
#
# Exits 1 with a clear message if any required value is missing or still
# holds a placeholder sentinel. Called by the Makefile; also safe to run
# standalone.
#
# Does NOT pull images, does NOT talk to Docker — pure shell.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/.env"

RED='\033[0;31m'
YEL='\033[0;33m'
GRN='\033[0;32m'
BLD='\033[1m'
RST='\033[0m'

ok()  { printf "  ${GRN}✓${RST} %s\n" "$*"; }
err() { printf "  ${RED}✗${RST} %s\n" "$*"; }
warn(){ printf "  ${YEL}!${RST} %s\n" "$*"; }

FAILED=0

# ── .env existence ────────────────────────────────────────────────────────────
if [[ ! -f "$ENV_FILE" ]]; then
  printf "${RED}${BLD}Error:${RST} .env not found.\n"
  printf "Run ${BLD}./setup.sh${RST} first.\n\n"
  exit 1
fi

# Load .env into the current shell (skip comments and blank lines)
set -o allexport
# shellcheck disable=SC1090
source <(grep -E '^[A-Z_]+=.' "$ENV_FILE" | grep -v '^#') 2>/dev/null || true
set +o allexport

get_raw() {
  grep -E "^${1}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d'=' -f2- | sed 's/#.*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true
}

# ── Sentinel / empty checker ──────────────────────────────────────────────────
SENTINELS=("replace-with-random-token" "xxx" "your-token-here" "changeme")

is_placeholder() {
  local val="$1"
  [[ -z "$val" ]] && return 0
  for s in "${SENTINELS[@]}"; do
    [[ "$val" == "$s" ]] && return 0
  done
  return 1
}

require() {
  local key="$1"
  local hint="$2"
  local val
  val="$(get_raw "$key")"
  if is_placeholder "$val"; then
    err "$key — $hint"
    FAILED=$((FAILED + 1))
  else
    ok "$key"
  fi
}

optional_warn() {
  local key="$1"
  local hint="$2"
  local val
  val="$(get_raw "$key")"
  if is_placeholder "$val"; then
    warn "$key not set — $hint"
  else
    ok "$key"
  fi
}

# ── Required checks ───────────────────────────────────────────────────────────
printf "\n${BLD}Pre-flight check${RST}\n"

require GITHUB_TOKEN           "GitHub PAT (repo + workflow scopes)"
require OPENCLAW_GATEWAY_TOKEN "Random token — run ./setup.sh to generate"
require PINCHTAB_TOKEN         "Random token — run ./setup.sh to generate"

# ── LLM auth ──────────────────────────────────────────────────────────────────
llm_auth_mode="$(get_raw LLM_AUTH_MODE)"
llm_auth_mode="${llm_auth_mode:-api_key}"

if [[ "$llm_auth_mode" == "oauth" ]]; then
  # OAuth mode: check that at least one OAuth profile exists in auth-profiles.json
  auth_file="${OPENCLAW_CONFIG_DIR:-$HOME/.openclaw}/agents/main/agent/auth-profiles.json"
  has_oauth=$(node -e "
    try {
      const p = JSON.parse(require('fs').readFileSync('${auth_file}','utf8')).profiles || {};
      const has = Object.values(p).some(v => v.mode === 'oauth' || v.type === 'oauth' || v.type === 'token');
      process.stdout.write(has ? 'yes' : 'no');
    } catch(_) { process.stdout.write('no'); }
  " 2>/dev/null)
  if [[ "$has_oauth" == "yes" ]]; then
    ok "LLM_AUTH_MODE=oauth (OAuth profiles found — run 'make login' to refresh)"
  else
    warn "LLM_AUTH_MODE=oauth but no OAuth profiles found — run: make login"
  fi
else
  # API key mode: at least one key required
  openai_val="$(get_raw OPENAI_API_KEY)"
  anthropic_val="$(get_raw ANTHROPIC_API_KEY)"
  if is_placeholder "$openai_val" && is_placeholder "$anthropic_val"; then
    err "LLM_AUTH_MODE=api_key but neither OPENAI_API_KEY nor ANTHROPIC_API_KEY is set"
    FAILED=$((FAILED + 1))
  else
    [[ -n "$openai_val" && ! $(is_placeholder "$openai_val") ]] && ok "OPENAI_API_KEY"
    [[ -n "$anthropic_val" && ! $(is_placeholder "$anthropic_val") ]] && ok "ANTHROPIC_API_KEY"
  fi
fi

# ── Config dir must exist on the host ─────────────────────────────────────────
config_dir="$(get_raw OPENCLAW_CONFIG_DIR)"

if [[ -z "$config_dir" ]]; then
  err "OPENCLAW_CONFIG_DIR is not set"
  FAILED=$((FAILED + 1))
elif [[ "$config_dir" == /c/* || "$config_dir" == /mnt/c/* ]]; then
  err "OPENCLAW_CONFIG_DIR looks like a Windows path: $config_dir"
  err "Update it in .env (e.g. \$HOME/.openclaw) and re-run."
  FAILED=$((FAILED + 1))
elif [[ ! -d "$config_dir" ]]; then
  warn "OPENCLAW_CONFIG_DIR does not exist: $config_dir"
  warn "Creating it now..."
  mkdir -p "$config_dir"
  ok "Created $config_dir"
else
  ok "OPENCLAW_CONFIG_DIR exists: $config_dir"
fi

# Workspace dir — derive from config dir if not set separately
workspace_dir="$(get_raw OPENCLAW_WORKSPACE_DIR)"
if [[ -n "$workspace_dir" && "$workspace_dir" != /c/* && "$workspace_dir" != /mnt/c/* ]]; then
  if [[ ! -d "$workspace_dir" ]]; then
    mkdir -p "$workspace_dir"
    ok "Created OPENCLAW_WORKSPACE_DIR: $workspace_dir"
  else
    ok "OPENCLAW_WORKSPACE_DIR exists"
  fi
fi

# ── Optional checks (warn only) ───────────────────────────────────────────────
printf "\n${BLD}Optional secrets${RST}\n"
optional_warn AZURE_DEVOPS_TOKEN   "needed for Azure DevOps repos"
optional_warn GOOGLE_REFRESH_TOKEN "needed for gcal/gmail commands"

# ── Result ────────────────────────────────────────────────────────────────────
printf "\n"
if [[ "$FAILED" -gt 0 ]]; then
  printf "${RED}${BLD}Pre-flight failed: %d issue(s).${RST}\n" "$FAILED"
  printf "Fix the errors above, then retry.\n\n"
  exit 1
fi

printf "${GRN}${BLD}Pre-flight passed.${RST}\n\n"
