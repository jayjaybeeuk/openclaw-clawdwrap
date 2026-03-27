#!/usr/bin/env bash
# setup.sh — One-click bootstrap for the OpenClaw Docker stack.
#
# What it does:
#   1. Creates .env from .env.example if .env is absent or empty.
#   2. Auto-generates random tokens for placeholder sentinel values.
#   3. Reports which secrets still need to be filled in before `docker compose up`.
#
# Idempotent: re-running never overwrites values you have already set.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$ROOT/.env"
EXAMPLE_FILE="$ROOT/.env.example"

# ── Colour helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'
YEL='\033[0;33m'
GRN='\033[0;32m'
CYN='\033[0;36m'
BLD='\033[1m'
RST='\033[0m'

info()    { printf "  ${CYN}•${RST} %s\n" "$*"; }
ok()      { printf "  ${GRN}✓${RST} %s\n" "$*"; }
warn()    { printf "  ${YEL}!${RST} %s\n" "$*"; }
err()     { printf "  ${RED}✗${RST} %s\n" "$*"; }
section() { printf "\n${BLD}%s${RST}\n" "$*"; }

# ── Step 1: Create .env if missing or empty ───────────────────────────────────
section "OpenClaw setup"

if [[ ! -f "$EXAMPLE_FILE" ]]; then
  err ".env.example not found — cannot bootstrap .env"
  exit 1
fi

if [[ ! -s "$ENV_FILE" ]]; then
  cp "$EXAMPLE_FILE" "$ENV_FILE"
  info "Created .env from .env.example"
else
  ok ".env already exists — skipping copy"
fi

# ── Helpers to read/write individual keys in .env ─────────────────────────────
get_env() {
  local key="$1"
  # Extract value after first '='; strip inline comments; trim whitespace
  # || true prevents grep's exit 1 (no match) from aborting under set -e pipefail
  grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d'=' -f2- | sed 's/#.*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true
}

set_env() {
  local key="$1"
  local value="$2"
  if grep -qE "^${key}=" "$ENV_FILE"; then
    # Replace existing line (portable sed — works on macOS and Linux)
    sed -i.bak "s|^${key}=.*|${key}=${value}|" "$ENV_FILE" && rm -f "${ENV_FILE}.bak"
  else
    printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
  fi
}

random_token() {
  # 32 bytes → 64 hex chars; falls back to /dev/urandom if openssl absent
  if command -v openssl &>/dev/null; then
    openssl rand -hex 32
  else
    LC_ALL=C tr -dc 'a-f0-9' < /dev/urandom | head -c 64
  fi
}

# ── Step 2: Auto-generate placeholder random tokens ───────────────────────────
section "Generating random tokens"

SENTINEL="replace-with-random-token"

for key in OPENCLAW_GATEWAY_TOKEN PINCHTAB_TOKEN; do
  current="$(get_env "$key")"
  if [[ "$current" == "$SENTINEL" || -z "$current" ]]; then
    token="$(random_token)"
    set_env "$key" "$token"
    ok "Generated $key"
  else
    ok "$key already set"
  fi
done

# ── Step 3: Platform hint for OPENCLAW_CONFIG_DIR ─────────────────────────────
section "Platform check"

config_dir="$(get_env OPENCLAW_CONFIG_DIR)"
if [[ "$config_dir" == /c/* || "$config_dir" == /mnt/c/* ]]; then
  warn "OPENCLAW_CONFIG_DIR looks like a Windows path: $config_dir"
  warn "On macOS/Linux, set it to a local path such as: \$HOME/.openclaw"
  warn "Edit .env to update it, then re-run this script."
else
  ok "OPENCLAW_CONFIG_DIR = $config_dir"
fi

# ── Step 4: Check required secrets ───────────────────────────────────────────
section "Secret checklist"

MISSING=0

check_required() {
  local key="$1"
  local hint="$2"
  local value
  value="$(get_env "$key")"
  if [[ -z "$value" ]]; then
    err "$key is empty  →  $hint"
    MISSING=$((MISSING + 1))
  else
    ok "$key is set"
  fi
}

check_optional() {
  local key="$1"
  local hint="$2"
  local value
  value="$(get_env "$key")"
  if [[ -z "$value" || "$value" == "xxx" ]]; then
    warn "$key not set  →  $hint (optional)"
  else
    ok "$key is set"
  fi
}

# Required for core stack
check_required GITHUB_TOKEN        "GitHub PAT with repo + workflow scopes"

# LLM auth — behaviour depends on LLM_AUTH_MODE
llm_auth_mode="$(get_env LLM_AUTH_MODE)"
llm_auth_mode="${llm_auth_mode:-api_key}"

if [[ "$llm_auth_mode" == "oauth" ]]; then
  ok "LLM_AUTH_MODE=oauth — run 'make login' after 'make up' to authenticate"
else
  openai_val="$(get_env OPENAI_API_KEY)"
  anthropic_val="$(get_env ANTHROPIC_API_KEY)"
  if [[ -z "$openai_val" && -z "$anthropic_val" ]]; then
    err "LLM_AUTH_MODE=api_key but no key set — set OPENAI_API_KEY or ANTHROPIC_API_KEY"
    err "  Or switch to OAuth: set LLM_AUTH_MODE=oauth and run 'make login'"
    MISSING=$((MISSING + 1))
  elif [[ -n "$openai_val" ]]; then
    ok "OPENAI_API_KEY is set (primary)"
    [[ -n "$anthropic_val" ]] && ok "ANTHROPIC_API_KEY is set (fallback)" || warn "ANTHROPIC_API_KEY not set — no fallback"
  else
    warn "OPENAI_API_KEY not set — Anthropic will be used as primary"
    ok "ANTHROPIC_API_KEY is set"
  fi
fi

# Optional — Azure DevOps agent support
check_optional AZURE_DEVOPS_TOKEN   "Azure DevOps PAT (only needed for ADO repos)"
check_optional AZURE_DEVOPS_ORG     "Azure DevOps organisation slug"
check_optional AZURE_DEVOPS_PROJECT "Azure DevOps project name"

# Optional — Google OAuth
check_optional GOOGLE_CLIENT_ID     "Google OAuth client ID"
check_optional GOOGLE_CLIENT_SECRET "Google OAuth client secret"
check_optional GOOGLE_REFRESH_TOKEN "Google OAuth refresh token"

# ── Step 5: Summary ───────────────────────────────────────────────────────────
section "Summary"

if [[ "$MISSING" -eq 0 ]]; then
  printf "\n${GRN}${BLD}All required secrets are set.${RST}\n"
  printf "\nNext steps:\n"
  printf "  1.  ${BLD}make up${RST}        — build images and start the stack\n"
  if [[ "$llm_auth_mode" == "oauth" ]]; then
    printf "  2.  ${BLD}make login${RST}     — authenticate OpenAI + Anthropic via web login (one-time)\n"
    printf "  3.  ${BLD}make validate${RST}  — confirm everything is wired\n\n"
  else
    printf "  2.  ${BLD}make validate${RST}  — confirm everything is wired\n\n"
  fi
else
  printf "\n${YEL}${BLD}%d required secret(s) still need filling in .env.${RST}\n" "$MISSING"
  printf "\nEdit ${BLD}.env${RST}, then re-run ${BLD}./setup.sh${RST} to verify.\n"
  printf "(${BLD}make up${RST} will also catch this before starting any containers.)\n\n"
fi
