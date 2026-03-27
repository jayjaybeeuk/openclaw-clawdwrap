# Agent Instructions (OpenClaw Docker Stack)

Start here when operating this stack:

1. Read `README.md` first.
2. Do not place secrets in repo files.
3. Keep `wrappers.yml` token source as `env:GITHUB_TOKEN`.

---

## LLM Auth

The stack supports two auth modes, controlled by `LLM_AUTH_MODE` in `.env`:

| Mode | How it works |
|---|---|
| `oauth` | OAuth profiles stored in `~/.openclaw/agents/main/agent/auth-profiles.json`. Set up via `make login`. No API credits needed. |
| `api_key` | API keys in `.env` (`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`). Injected into `auth-profiles.json` on startup. |

OAuth profiles survive container restarts. The startup script (`start-gateway.sh`) never
overwrites OAuth profiles, even if API keys are present in `.env`.

---

## Runtime secrets

Runtime tokens live in `/run/openclaw/env` inside the `openclaw_run` Docker volume.
Sync from `.env` with:

```bash
make inject-tokens
```

Required keys in `/run/openclaw/env`:
- `GITHUB_TOKEN` — GitHub PAT (repo + workflow scopes)
- `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` / `GOOGLE_REFRESH_TOKEN` — Google OAuth (optional)
- `AZURE_DEVOPS_TOKEN` — Azure DevOps PAT (optional)

Google behavior: `gcal`/`gmail` mint short-lived access tokens from `GOOGLE_REFRESH_TOKEN`
at call time — no periodic token refresh job required.

---

## Validation

```bash
make validate
docker compose exec clawwrapd sh -lc "claw-wrap check"
docker compose exec openclaw-gateway sh -lc "gh auth status --hostname github.com"
```

---

## Google tools

Wrapped Google commands are available in the gateway PATH:

- `gcal` — Google Calendar
- `gmail` — Gmail send

For calendar/email tasks, prefer these directly. Quick checks:

```bash
docker compose exec openclaw-gateway sh -lc "gcal list-calendars"
docker compose exec openclaw-gateway sh -lc "gmail --help"
```

---

## PinchTab

This stack runs PinchTab bridge in Docker headless mode.

- Use `pinch ...` commands directly.
- Default workflow: `pinch nav` → `pinch snap -i -c` → `pinch text --raw` → `pinch click/type`.
- Do not ask to attach a Chrome tab/extension unless relay mode is explicitly configured.

---

## Policy intent

- Allow branch pushes and PR creation.
- Never allow direct push/update/delete on `main`/`master`.
- Keep destructive push flags blocked.

If modifying `wrappers.yml`, preserve the above intent.

---

## Agent-Runner branch naming

Agent PRs **must** use: `agent/<issue-number>-<slug>`

- `<issue-number>` — GitHub issue ID or Azure DevOps work item ID
- `<slug>` — kebab-case summary, max 40 chars, alphanumeric + hyphens only
- Examples: `agent/42-fix-login-redirect`, `agent/101-add-dark-mode`

Direct pushes to `main`/`master` are blocked by `wrappers.yml`.

---

## GitHub MCP Tools

Available as `mcp__github__*` in the OpenClaw gateway:

- `mcp__github__list_issues` — list open issues from a repo
- `mcp__github__issue_read` — read a single issue by number
- `mcp__github__issue_write` — create/update issues, apply labels, add comments
- `mcp__github__create_pull_request` — open a PR from a feature branch
- `mcp__github__pull_request_read` — read PR details
- `mcp__github__add_issue_comment` — post a comment on an issue

These use `GITHUB_TOKEN` injected via `openclaw_run`. No extra auth required.

---

## Environment variables

| Variable | Purpose |
|---|---|
| `LLM_AUTH_MODE` | `oauth` (web login via `make login`) or `api_key` (API keys in `.env`) |
| `OPENAI_API_KEY` | OpenAI API key — only used when `LLM_AUTH_MODE=api_key` |
| `ANTHROPIC_API_KEY` | Anthropic API key — only used when `LLM_AUTH_MODE=api_key` |
| `GITHUB_TOKEN` | GitHub PAT (repo + workflow scopes) |
| `AZURE_DEVOPS_TOKEN` | PAT for Azure DevOps REST API (optional) |
| `AZURE_DEVOPS_ORG` | Azure DevOps organisation slug (optional) |
| `AZURE_DEVOPS_PROJECT` | Azure DevOps project name (optional) |
| `AGENT_MAX_CONCURRENCY` | Max parallel issue runs (default: `1`) |
| `AGENT_DRY_RUN` | Skip `git push` and `gh pr create` when `true` (default: `false`) |
| `AGENT_POLL_INTERVAL_SECS` | How often to poll for new issues in seconds (default: `300`) |
