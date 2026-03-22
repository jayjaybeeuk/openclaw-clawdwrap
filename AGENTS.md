# Agent Instructions (OpenClaw Docker Stack)

Start here when operating this stack:

1. Read `README.md` first.
2. Do not place secrets in repo files.
3. Keep `wrappers.yml` token source as `env:GITHUB_TOKEN`.
4. Put runtime tokens only in `/run/openclaw/env` via `openclaw_run` volume (`GITHUB_TOKEN`, optional `GOOGLE_CLIENT_ID`/`GOOGLE_CLIENT_SECRET`/`GOOGLE_REFRESH_TOKEN`).
   - Sync from `.env`:
     `powershell -Command "$wanted=@('GITHUB_TOKEN','GOOGLE_CLIENT_ID','GOOGLE_CLIENT_SECRET','GOOGLE_REFRESH_TOKEN'); $map=@{}; Get-Content .env | %% { $line=$_.Trim(); if(-not $line -or $line.StartsWith('#')){return}; $idx=$line.IndexOf('='); if($idx -lt 1){return}; $k=$line.Substring(0,$idx).Trim(); $v=$line.Substring($idx+1); if($wanted -contains $k){$map[$k]=$v} }; if(-not $map['GITHUB_TOKEN']){ throw 'GITHUB_TOKEN missing in .env' }; $lines=@(); foreach($k in $wanted){ if($map[$k]){ $lines += \"$k=$($map[$k])\" } }; [IO.File]::WriteAllText('.env.runtime.generated', (($lines -join \"`n\") + \"`n\"), (New-Object Text.UTF8Encoding($false))); docker run --rm -v ${PWD}/.env.runtime.generated:/tmp/runtime.env:ro -v openclaw-docker-stack_openclaw_run:/run/openclaw alpine sh -lc 'umask 077; cp /tmp/runtime.env /run/openclaw/env; chown 1000:1000 /run/openclaw/env; chmod 600 /run/openclaw/env'; cmd /c \"del /f /q .env.runtime.generated\"; docker compose restart clawwrapd openclaw-gateway"`
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
