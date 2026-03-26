# Agent Instructions (OpenClaw Docker Stack)

Start here when operating this stack:

1. Read `README.md` first.
2. Do not place secrets in repo files.
3. Keep `wrappers.yml` token source as `env:GITHUB_TOKEN`.
4. Put runtime tokens only in `/run/openclaw/env` via `openclaw_run` volume (`GITHUB_TOKEN`, `ANTHROPIC_API_KEY`, optional `AZURE_DEVOPS_TOKEN`, `GOOGLE_CLIENT_ID`/`GOOGLE_CLIENT_SECRET`/`GOOGLE_REFRESH_TOKEN`).
   - Sync from `.env`:
     `powershell -Command "$wanted=@('GITHUB_TOKEN','ANTHROPIC_API_KEY','AZURE_DEVOPS_TOKEN','GOOGLE_CLIENT_ID','GOOGLE_CLIENT_SECRET','GOOGLE_REFRESH_TOKEN'); $map=@{}; Get-Content .env | %% { $line=$_.Trim(); if(-not $line -or $line.StartsWith('#')){return}; $idx=$line.IndexOf('='); if($idx -lt 1){return}; $k=$line.Substring(0,$idx).Trim(); $v=$line.Substring($idx+1); if($wanted -contains $k){$map[$k]=$v} }; if(-not $map['GITHUB_TOKEN']){ throw 'GITHUB_TOKEN missing in .env' }; if(-not $map['ANTHROPIC_API_KEY']){ throw 'ANTHROPIC_API_KEY missing in .env' }; $lines=@(); foreach($k in $wanted){ if($map[$k]){ $lines += \"$k=$($map[$k])\" } }; [IO.File]::WriteAllText('.env.runtime.generated', (($lines -join \"`n\") + \"`n\"), (New-Object Text.UTF8Encoding($false))); docker run --rm -v ${PWD}/.env.runtime.generated:/tmp/runtime.env:ro -v openclaw-docker-stack_openclaw_run:/run/openclaw alpine sh -lc 'umask 077; cp /tmp/runtime.env /run/openclaw/env; chown 1000:1000 /run/openclaw/env; chmod 600 /run/openclaw/env'; cmd /c \"del /f /q .env.runtime.generated\"; docker compose restart clawwrapd openclaw-gateway agent-runner"`
   - Google behavior: `gcal`/`gmail` mint short-lived access tokens from `GOOGLE_REFRESH_TOKEN` at call time (no periodic token refresh job).
5. Validate with:
   - `docker compose exec clawwrapd sh -lc "claw-wrap check"`
   - `docker compose exec openclaw-gateway sh -lc "gh auth status --hostname github.com"`

Google tool capability:

- Wrapped Google commands are available in the gateway PATH:
  - `gcal` (Google Calendar)
  - `gmail` (Gmail send)
- For calendar/email tasks, prefer these commands directly instead of asking for extra auth steps.
- Quick checks:
  - `docker compose exec openclaw-gateway sh -lc "gcal list-calendars"`
  - `docker compose exec openclaw-gateway sh -lc "gmail --help"`

Policy intent:

- Allow branch pushes and PR creation.
- Never allow direct push/update/delete on `main`/`master`.
- Keep destructive push flags blocked.

If modifying policy, preserve the above intent.

PinchTab mode note:

- This stack runs PinchTab bridge in Docker headless mode.
- Agents should use `pinch ...` commands directly and should not ask for Chrome extension tab attachment unless relay mode is explicitly configured.

## OpenClaw Runtime Policy

Environment policy (OpenClaw Docker stack):

- Browser automation: use PinchTab CLI (`pinch ...`) directly.
- Default workflow: `pinch nav`, `pinch snap -i -c`, `pinch text --raw`, then `pinch click/type`.
- Do not ask to attach a Chrome tab/extension unless `pinch` is unavailable.
- For Google tasks, use `gcal`/`gmail` directly.
- Before asking for re-auth, verify with `claw-wrap check`.

## Agent-Runner Branch Naming Convention

Agent PRs **must** use the branch naming pattern: `agent/<issue-number>-<slug>`

- `<issue-number>` is the numeric GitHub issue ID or Azure DevOps work item ID.
- `<slug>` is a short kebab-case summary of the issue title (max 40 chars, alphanumeric + hyphens only).
- Examples: `agent/42-fix-login-redirect`, `agent/101-add-dark-mode`

Direct pushes to `main`/`master` remain blocked by `wrappers.yml` policy.

## GitHub MCP Tools (P5-001)

The following MCP tools (`mcp__github__*`) are available in the OpenClaw gateway for issue and PR operations:

- `mcp__github__list_issues` — list open issues from a repo
- `mcp__github__issue_read` — read a single issue by number
- `mcp__github__issue_write` — create/update issues, apply labels, add comments
- `mcp__github__create_pull_request` — open a PR from a feature branch
- `mcp__github__pull_request_read` — read PR details
- `mcp__github__add_issue_comment` — post a comment on an issue

These tools use the `GITHUB_TOKEN` credential injected via `openclaw_run`. No extra auth setup is required.

## Environment Variables (agent-runner)

| Variable | Purpose |
|---|---|
| `ANTHROPIC_API_KEY` | Authenticates `claude` CLI and `@anthropic-ai/sdk` inside `agent-runner` |
| `AZURE_DEVOPS_TOKEN` | PAT for Azure DevOps REST API (optional if only targeting GitHub) |
| `AZURE_DEVOPS_ORG` | Azure DevOps organisation slug |
| `AZURE_DEVOPS_PROJECT` | Azure DevOps project name |
| `AGENT_MAX_CONCURRENCY` | Max parallel issue runs (default: `1`) |
| `AGENT_DRY_RUN` | Skip `git push` and `gh pr create` when `true` (default: `false`) |
| `AGENT_POLL_INTERVAL_SECS` | How often to poll for new issues in seconds (default: `300`) |
