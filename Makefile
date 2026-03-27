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
	@printf "\n\033[0;32m✓\033[0m Stack is up. Waiting for gateway...\n"
	@for i in 1 2 3 4 5 6 7 8 9 10; do \
	  url=$$(docker compose logs openclaw-gateway 2>/dev/null | grep "Dashboard URL:" | tail -1 | sed 's/.*Dashboard URL: //'); \
	  if [ -n "$$url" ]; then \
	    printf "\n\033[1mDashboard URL:\033[0m $$url\n\n"; \
	    open "$$url" 2>/dev/null || true; \
	    exit 0; \
	  fi; \
	  sleep 2; \
	done; \
	printf "\nGateway not ready yet — run \033[1mmake url\033[0m once it starts.\n\n"

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

.PHONY: login
login:  ## Authenticate all providers (runs login-openai then login-anthropic)
	@$(MAKE) login-openai
	@$(MAKE) login-anthropic

.PHONY: login-openai
login-openai:  ## Authenticate OpenAI Codex via OAuth (ChatGPT Team — browser flow)
	@printf "\n\033[1mOpenAI Codex login (ChatGPT Team subscription)\033[0m\n"
	@printf "A browser window will open. Sign in with your ChatGPT account.\n\n"
	docker compose exec -it openclaw-gateway openclaw models auth login --provider openai-codex --set-default
	@printf "\n\033[0;32m✓\033[0m OpenAI auth done.\n\n"

.PHONY: login-anthropic
login-anthropic:  ## Authenticate Anthropic via Claude token (Claude Team — paste flow)
	@printf "\n\033[1mAnthropic login (Claude Team subscription)\033[0m\n"
	@printf "1. Run this in a separate terminal:  \033[1mclaude setup-token\033[0m\n"
	@printf "2. Copy the token it prints.\n"
	@printf "3. Paste it at the prompt below.\n\n"
	docker compose exec -it openclaw-gateway openclaw models auth paste-token --provider anthropic
	@printf "\n\033[0;32m✓\033[0m Anthropic auth done.\n\n"

.PHONY: approve-devices
approve-devices:  ## Approve all pending browser pairing requests
	@echo "Pending device requests:"
	@docker compose exec openclaw-gateway sh -c "openclaw devices list 2>&1"
	@printf "\nApproving all pending requests...\n"
	@docker compose exec openclaw-gateway sh -c "\
	  openclaw devices list 2>/dev/null \
	  | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' \
	  | while read id; do openclaw devices approve \"\$$id\" 2>&1; done" \
	  || true
	@printf "\nDone. Refresh the dashboard in your browser.\n"

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
	@printf "  \033[1mFirst time?\033[0m  Run:  make setup  →  fill .env  →  make up  →  make login\n\n"
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*##"}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
	@printf "\n"
