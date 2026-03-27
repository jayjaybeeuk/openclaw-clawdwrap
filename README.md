# OpenClaw Docker Stack (Portable, Secret-Free)

This folder is a portable deployment package for:

- OpenClaw gateway/CLI
- PinchTab bridge
- claw-wrap daemon (GitHub auth proxy for `gh`/`git`)

## Quick Start

> Prerequisites: [Docker Desktop](https://www.docker.com/products/docker-desktop/) and `make`.

```bash
# 1. Bootstrap — creates .env and generates random tokens
make setup

# 2. Fill in your secrets — edit .env:
#
#    GITHUB_TOKEN        — required. GitHub PAT (repo + workflow scopes)
#                          github.com → Settings → Developer settings → Personal access tokens
#
#    LLM_AUTH_MODE       — controls how AI providers authenticate:
#                          oauth    = use `make login` (ChatGPT Team / Claude Team web accounts)
#                          api_key  = use OPENAI_API_KEY / ANTHROPIC_API_KEY below
#
#    OPENCLAW_CONFIG_DIR — local path e.g. $HOME/.openclaw
$EDITOR .env

# 3. Build images and start the stack (preflight check runs automatically)
#    Browser opens automatically with the tokenised dashboard URL.
make up

# 4. Authenticate LLM providers (one-time, OAuth mode only)
#    Skipped if LLM_AUTH_MODE=api_key
make login

# 5. Confirm everything is wired
make validate
```

Bookmark the dashboard URL that opens — it contains your auth token in the hash.
Run `make url` at any time to reprint it.
Run `make help` to see all available commands.

---

## LLM Authentication

### OAuth mode (recommended — no API credits needed)

Set `LLM_AUTH_MODE=oauth` in `.env`. Then after `make up`, run:

```bash
make login          # runs both steps below in sequence
make login-openai   # OpenAI Codex — browser OAuth via ChatGPT Team account
make login-anthropic # Anthropic — paste a token from `claude setup-token`
```

OAuth tokens are stored in `~/.openclaw/agents/main/agent/auth-profiles.json` (on the
host, mounted into the container). They survive container restarts and rebuilds.

After re-running `make login-openai`, restart the gateway to pick up the new profile:

```bash
docker compose restart openclaw-gateway
```

### API key mode

Set `LLM_AUTH_MODE=api_key` in `.env` and fill in:

```bash
OPENAI_API_KEY=sk-proj-...     # platform.openai.com/api-keys
ANTHROPIC_API_KEY=sk-ant-...   # platform.anthropic.com/settings/keys (requires API credits)
```

OpenAI is tried first; Anthropic is the fallback. At least one is required.

> **Note:** Anthropic API credits are separate from claude.ai Team/Pro subscriptions.
> If you have a Claude Team account, use OAuth mode instead.

---

## Dashboard access

`make up` opens the browser automatically. The URL format is:

```
http://127.0.0.1:18789/#token=<your-gateway-token>
```

Always use `127.0.0.1`, not `localhost` — they are treated as different origins by the
browser and the token stored for one will not work for the other.

---

## Security model

- `wrappers.yml` defines *policy* and *credential names*.
- Real secrets are **not** stored in repo files.
- Runtime token is read from `/run/openclaw/env` in Docker volume `openclaw_run`.

---

## Files

- `docker-compose.yml` — services and mounts
- `Dockerfile` — OpenClaw gateway/CLI image (built from npm)
- `Dockerfile.openclaw-tools` — claw-wrap daemon image with `gh` + `git`
- `wrappers.yml` — claw-wrap tool policy
- `.env.example` — environment template (safe to commit)
- `AGENTS.md` / `CLAUDE.md` — AI-agent runbook entrypoint

## Scripts

- `setup.sh` — one-click bootstrap: creates `.env` from `.env.example`, generates random tokens
- `Makefile` — convenience targets (`make up`, `make login`, `make validate`, …). Run `make help`.
- `scripts/preflight.sh` — validates `.env` before any container starts; called automatically by `make up`
- `scripts/start-gateway.sh` — gateway entrypoint; seeds allowed origins, preserves OAuth profiles,
  injects API keys only when `LLM_AUTH_MODE=api_key`, prints the tokenised dashboard URL
- `scripts/inject-tokens.sh` — pushes runtime secrets from `.env` into the `openclaw_run` Docker volume
- `scripts/dashboard-url.sh` — prints the tokenised Control UI URL
- `scripts/gcal-wrap.sh` — Google Calendar wrapper; mints a short-lived access token from `GOOGLE_REFRESH_TOKEN` at call time
- `scripts/gmail-wrap.sh` — Gmail wrapper; mints a short-lived access token from `GOOGLE_REFRESH_TOKEN` at call time
- `scripts/refresh-google-token.sh` — helper for refreshing Google OAuth credentials manually

---

## Rebuilding after script changes

`scripts/start-gateway.sh` is baked into the Docker image at build time. After editing it,
rebuild before restarting:

```bash
docker compose build openclaw-gateway
docker compose up -d openclaw-gateway
```

---

## Validate

```bash
make validate
# or individually:
docker compose exec clawwrapd sh -lc "claw-wrap check"
docker compose exec openclaw-gateway sh -lc "gh auth status --hostname github.com"
docker compose exec openclaw-gateway sh -lc "gcal list-calendars"
```

---

## Git policy (current)

- Branch pushes allowed.
- Direct updates/deletes to `main`/`master` blocked by wrapper policy.
- Force/mirror/delete push flags blocked.
- `gh auth login/logout/token/...` blocked (token injection model).

Still enforce branch protection in GitHub for hard guarantees.

---

## Safe migration to a public repo

Never commit:
- `.env`
- `/run/openclaw/env`
- real tokens, session keys, or OAuth profiles

Safe to commit:
- `docker-compose.yml`, `Dockerfile`, `Dockerfile.openclaw-tools`
- `wrappers.yml`, `.env.example`, docs
