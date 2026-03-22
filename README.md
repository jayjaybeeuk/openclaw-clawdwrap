# OpenClaw Docker Stack (Portable, Secret-Free)

This folder is a portable deployment package for:

- OpenClaw gateway/CLI
- PinchTab bridge
- claw-wrap daemon (GitHub auth proxy for `gh`/`git`)

## Security model

- `wrappers.yml` defines *policy* and *credential names*.
- Real secrets are **not** stored in repo files.
- Runtime token is read from `/run/openclaw/env` in Docker volume `openclaw_run`.

## Files

- `docker-compose.yml` - services and mounts
- `Dockerfile` - standalone OpenClaw base image built from npm
- `Dockerfile.openclaw-tools` - OpenClaw image with claw-wrap + gh + git
- `wrappers.yml` - claw-wrap tool policy
- `.env.example` - environment template (safe to commit)
- `AGENTS.md` / `CLAUDE.md` - AI-agent runbook entrypoint

## Scripts

- `scripts/start-gateway.sh` - gateway entrypoint used by the Docker stack; seeds
  Control UI allowed origins, prints a tokenized dashboard URL hint, and starts
  the gateway with the configured bind/port/token.
- `scripts/dashboard-url.sh` - prints the tokenized Control UI URL via
  `openclaw dashboard --no-open`.
- `scripts/gcal-wrap.sh` - Google Calendar wrapper used by `gcal`; mints a
  short-lived access token from `GOOGLE_REFRESH_TOKEN` at call time.
- `scripts/gmail-wrap.sh` - Gmail wrapper used by `gmail`; mints a short-lived
  access token from `GOOGLE_REFRESH_TOKEN` at call time.
- `scripts/refresh-google-token.sh` - helper for refreshing Google OAuth
  credentials manually when needed.

## First setup on a host

1. Copy this folder to your target machine.
2. Create `.env` from `.env.example`.
3. Optionally pin the npm package/version used for the base image:

```powershell
# Example: keep the latest published release
OPENCLAW_NPM_SPEC=openclaw@latest
```

When `OPENCLAW_GATEWAY_BIND` is not `loopback`, the stack automatically allows
Control UI origins for `http://localhost:<port>` and `http://127.0.0.1:<port>`.
If you want to open the UI from another machine, set
`OPENCLAW_CONTROL_UI_ALLOWED_ORIGINS` to a comma-separated list such as
`http://192.168.1.50:18789,http://openclaw.local:18789`.

4. Build service images:

```powershell
docker compose build
```

This folder is now self-contained: `docker compose build` builds the local
OpenClaw gateway/CLI image from `Dockerfile` and builds `clawwrapd` from
`Dockerfile.openclaw-tools`, without depending on files outside this folder.

5. Permissions preflight:

```powershell
docker run --rm -v C:\Users\User\.openclaw:/dst alpine sh -lc "chown -R 1000:1000 /dst && chmod -R u+rwX,go+rX /dst"
```

6. Set runtime GitHub + Google OAuth credentials:

```powershell
docker run --rm -v openclaw-docker-stack_openclaw_run:/run/openclaw alpine sh -lc "umask 077; printf 'GITHUB_TOKEN=ghp_or_github_pat_here\nGOOGLE_CLIENT_ID=google_client_id_here\nGOOGLE_CLIENT_SECRET=google_client_secret_here\nGOOGLE_REFRESH_TOKEN=google_refresh_token_here\n' > /run/openclaw/env; chown 1000:1000 /run/openclaw/env; chmod 600 /run/openclaw/env"
```

Update runtime tokens from `.env` (no manual paste):

```powershell
$wanted = @('GITHUB_TOKEN','GOOGLE_CLIENT_ID','GOOGLE_CLIENT_SECRET','GOOGLE_REFRESH_TOKEN')
$map = @{}
Get-Content .env | ForEach-Object {
  $line = $_.Trim()
  if (-not $line -or $line.StartsWith('#')) { return }
  $idx = $line.IndexOf('=')
  if ($idx -lt 1) { return }
  $k = $line.Substring(0,$idx).Trim()
  $v = $line.Substring($idx+1)
  if ($wanted -contains $k) { $map[$k] = $v }
}
if (-not $map['GITHUB_TOKEN']) { throw "GITHUB_TOKEN missing in .env" }
$lines = @()
foreach ($k in $wanted) { if ($map[$k]) { $lines += "$k=$($map[$k])" } }
[IO.File]::WriteAllText(".env.runtime.generated", (($lines -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
docker run --rm -v ${PWD}/.env.runtime.generated:/tmp/runtime.env:ro -v openclaw-docker-stack_openclaw_run:/run/openclaw alpine sh -lc "umask 077; cp /tmp/runtime.env /run/openclaw/env; chown 1000:1000 /run/openclaw/env; chmod 600 /run/openclaw/env"
cmd /c "del /f /q .env.runtime.generated"
docker compose restart clawwrapd openclaw-gateway
```

Required `.env` keys for Google on-demand token minting:

```bash
GOOGLE_CLIENT_ID=...
GOOGLE_CLIENT_SECRET=...
GOOGLE_REFRESH_TOKEN=...
```

`gcal` and `gmail` mint a fresh Google access token from `GOOGLE_REFRESH_TOKEN` on each call.
No periodic refresh job and no restart is required for access-token expiry.

One-time OAuth code exchange (client ID prefilled):

```bash
curl -sS https://oauth2.googleapis.com/token \
  --data-urlencode "code=PASTE_CODE_HERE" \
  --data-urlencode "client_id=288821957916-ef089saqjkeqgvlchi32f010aepk0pks.apps.googleusercontent.com" \
  --data-urlencode "client_secret=PASTE_CLIENT_SECRET_HERE" \
  --data-urlencode "redirect_uri=http://localhost" \
  --data-urlencode "grant_type=authorization_code"
```

7. Start services:

```powershell
docker compose up -d
```

or restart:

```powershell
docker compose restart clawwrapd openclaw-gateway
```

8. Open the dashboard with the gateway token already embedded.

Print the tokenized URL:

```powershell
docker compose exec openclaw-gateway sh -lc "openclaw-dashboard-url"
```

You can also inspect the gateway startup logs; the container prints the same
dashboard URL on boot when `OPENCLAW_GATEWAY_TOKEN` is set.

Why this is manual-by-design:

- `clawwrapd` protects wrapped CLI tools like `gh` and `git`; it does not log
  the browser dashboard in automatically.
- The Control UI authenticates separately over the Gateway WebSocket.
- The supported convenience flow is a tokenized dashboard URL, which stores the
  token in the browser's local storage on first open.

## Validate

```powershell
docker compose exec clawwrapd sh -lc "claw-wrap check"
docker compose exec openclaw-gateway sh -lc "gh auth status --hostname github.com"
docker compose exec openclaw-gateway sh -lc "gh api user --jq '.login'"
docker compose exec openclaw-gateway sh -lc "gcal list-calendars"
```

## Git policy (current)

- Branch pushes allowed.
- Direct updates/deletes to `main`/`master` blocked by wrapper policy.
- Force/mirror/delete push flags blocked.
- `gh auth login/logout/token/...` blocked (token injection model).

Still enforce branch protection in GitHub for hard guarantees.

## Safe migration to a public repo

- Keep this folder and commit only:
  - `docker-compose.yml`
  - `Dockerfile`
  - `Dockerfile.openclaw-tools`
  - `wrappers.yml`
  - `.env.example`
  - docs
- Never commit:
  - `.env`
  - `/run/openclaw/env`
  - real tokens/session keys
