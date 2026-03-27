#!/usr/bin/env bash
# scripts/inject-tokens.sh — Inject runtime secrets from .env into the
# openclaw_run Docker volume (/run/openclaw/env).
#
# This is the bash equivalent of the PowerShell one-liner in README.md.
# Run after `docker compose up -d` when secrets change.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/.env"

RED='\033[0;31m'
GRN='\033[0;32m'
BLD='\033[1m'
RST='\033[0m'

ok()  { printf "  ${GRN}✓${RST} %s\n" "$*"; }
err() { printf "  ${RED}✗${RST} %s\n" "$*"; }

if [[ ! -f "$ENV_FILE" ]]; then
  err ".env not found — run ./setup.sh first"
  exit 1
fi

# Keys written to the runtime volume (never the full .env)
RUNTIME_KEYS=(
  GITHUB_TOKEN
  ANTHROPIC_API_KEY
  AZURE_DEVOPS_TOKEN
  GOOGLE_CLIENT_ID
  GOOGLE_CLIENT_SECRET
  GOOGLE_REFRESH_TOKEN
)

# Build the runtime env file content from .env
runtime_content=""
for key in "${RUNTIME_KEYS[@]}"; do
  val="$(grep -E "^${key}=" "$ENV_FILE" | head -1 | cut -d'=' -f2- | sed 's/#.*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  if [[ -n "$val" ]]; then
    runtime_content+="${key}=${val}"$'\n'
  fi
done

if [[ -z "$runtime_content" ]]; then
  err "No runtime keys found in .env (checked: ${RUNTIME_KEYS[*]})"
  exit 1
fi

# Detect compose project name for the volume prefix
COMPOSE_PROJECT="${COMPOSE_PROJECT_NAME:-$(basename "$ROOT" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/-*$//')}"
VOLUME="${COMPOSE_PROJECT}_openclaw_run"

printf "\n${BLD}Injecting runtime tokens into volume: %s${RST}\n" "$VOLUME"

# Write via a temporary container (no host file written)
printf '%s' "$runtime_content" | docker run --rm -i \
  -v "${VOLUME}:/run/openclaw" \
  alpine sh -c "umask 077; cat > /run/openclaw/env; chown 1000:1000 /run/openclaw/env; chmod 600 /run/openclaw/env"

ok "Tokens written to /run/openclaw/env"

printf "\n${BLD}Restarting services to pick up new tokens...${RST}\n"
docker compose --project-directory "$ROOT" restart clawwrapd openclaw-gateway agent-runner 2>/dev/null \
  || docker compose --project-directory "$ROOT" restart clawwrapd openclaw-gateway

ok "Done. Validate with: make validate\n"
