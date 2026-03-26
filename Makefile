# Makefile — OpenClaw Docker stack shortcuts.
# Usage: make <target>
# Requires: bash, docker, docker compose v2

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

# ── Bootstrap ─────────────────────────────────────────────────────────────────

.PHONY: setup
setup:  ## Copy .env.example → .env and generate random tokens
	@bash setup.sh

# ── Core lifecycle ────────────────────────────────────────────────────────────

.PHONY: up
up: preflight  ## Preflight check + build images + start all services
	docker compose build
	docker compose up -d
	@printf "\n\033[0;32m✓\033[0m Stack is up. Get the dashboard URL:\n"
	@printf "  make url\n\n"

.PHONY: down
down:  ## Stop and remove all containers (volumes are preserved)
	docker compose down

.PHONY: restart
restart:  ## Restart all services
	docker compose restart

.PHONY: rebuild
rebuild: preflight  ## Force-rebuild all images then restart
	docker compose build --no-cache
	docker compose up -d

# ── Preflight (internal + standalone) ─────────────────────────────────────────

.PHONY: preflight
preflight:  ## Run pre-flight checks without starting anything
	@bash scripts/preflight.sh

# ── Runtime token injection ───────────────────────────────────────────────────

.PHONY: inject-tokens
inject-tokens:  ## Inject runtime secrets from .env into the openclaw_run volume
	@bash scripts/inject-tokens.sh

# ── Inspection helpers ────────────────────────────────────────────────────────

.PHONY: url
url:  ## Print the tokenized Control UI dashboard URL
	@docker compose exec openclaw-gateway sh -lc "openclaw-dashboard-url" 2>/dev/null \
	  || printf "Gateway is not running. Try: make up\n"

.PHONY: validate
validate:  ## Validate claw-wrap policy and GitHub auth inside running containers
	@printf "\n\033[1mValidating claw-wrap policy...\033[0m\n"
	docker compose exec clawwrapd sh -lc "claw-wrap check"
	@printf "\n\033[1mChecking GitHub auth...\033[0m\n"
	docker compose exec openclaw-gateway sh -lc "gh auth status --hostname github.com"
	docker compose exec openclaw-gateway sh -lc "gh api user --jq '.login'"

.PHONY: logs
logs:  ## Follow logs for all services (Ctrl-C to stop)
	docker compose logs -f

.PHONY: logs-gateway
logs-gateway:  ## Follow logs for openclaw-gateway only
	docker compose logs -f openclaw-gateway

.PHONY: ps
ps:  ## Show running container status
	docker compose ps

# ── Help ──────────────────────────────────────────────────────────────────────

.PHONY: help
help:  ## Show this help message
	@printf "\n\033[1mOpenClaw stack\033[0m\n\n"
	@printf "  \033[1mFirst time?\033[0m  Run:  make setup  →  fill .env  →  make up\n\n"
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*##"}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
	@printf "\n"
