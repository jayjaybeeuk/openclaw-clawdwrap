# OpenClaw Issue Tracker

Issues identified in the codebase review (2026-04-19).
Tick each off as fixed.

---

## 🔴 High — can silently break things

- [x] **H1** `refresh-google-token --sync-runtime` nukes `ANTHROPIC_API_KEY` and `AZURE_DEVOPS_TOKEN`
  - Both `refresh-google-token.sh` and `refresh-google-token.ps1` rebuild `/run/openclaw/env` from
    scratch using only GitHub + Google keys, dropping any ANTHROPIC/Azure keys written earlier by
    `inject-tokens`.
  - Fix: read and include `ANTHROPIC_API_KEY` and `AZURE_DEVOPS_TOKEN` from `.env` in the sync block.
  - Files: `scripts/refresh-google-token.sh`, `scripts/refresh-google-token.ps1`

- [x] **H2** Hardcoded personal git identity defaults ship to all users
  - `docker-compose.yml` and `.env.example` defaulted `GIT_AUTHOR_*` / `GIT_COMMITTER_*` to
    `James Bolton / jayjaybeeuk@gmail.com`. Any clone without `.env` overrides got agent commits
    attributed to the wrong person.
  - Initial fix (empty-string defaults in compose) was itself risky: git treats an empty
    `GIT_AUTHOR_NAME` as authoritative and fails with "empty ident" instead of falling back to
    `~/.gitconfig`. Revised fix: keep empty defaults in compose so the vars are forwarded when set;
    unset any that arrive empty at the top of `start-gateway.sh` so git can fall back normally.
  - Files: `docker-compose.yml`, `.env.example`, `scripts/start-gateway.sh`

---

## 🟡 Medium — causes confusion or maintenance pain

- [x] **M1** `mint_access_token()` and `require_oauth()` duplicated across gcal + gmail wrappers
  - `gcal-wrap.sh` and `gmail-wrap.sh` are byte-for-byte identical in their top ~35 lines.
    A bug or API change in the token minting logic needs fixing in two places.
  - Fix: extract to `scripts/google-auth-lib.sh`; source it from both wrappers.
  - Files: `scripts/gcal-wrap.sh`, `scripts/gmail-wrap.sh`

- [ ] **M2** `Read-EnvValue` duplicated across PowerShell scripts
  - `token-health.ps1` and `refresh-google-token.ps1` each define their own version with slightly
    different comment-stripping behaviour.
  - Fix: extract to a new `scripts/env-utils.ps1` (not `runtime-volume.ps1` — keep that focused);
    dot-source it from both scripts.
  - Files: `scripts/token-health.ps1`, `scripts/refresh-google-token.ps1`

- [ ] **M3** No `.dockerignore` — full context (including `.git/`) sent on every build
  - Fix: add `.dockerignore` at repo root excluding `.git`, `.env`, `*.md`, `personalities/`, etc.

- [ ] **M5** `inject-tokens.ps1` error says "run ./setup.sh" — bash-only on Windows
  - A Windows-native user without WSL cannot run `setup.sh`.
  - Fix: update the error message to mention WSL, or create `setup.ps1`.
  - Files: `scripts/inject-tokens.ps1`

---

## 🟢 Low — cleanup / polish

- [ ] **L1** Dockerfile wrapper scripts are unmaintainable `printf` soup
  - `gh`, `git`, `git-askpass-runtime`, and `pinch` wrappers are generated via escape-heavy
    `printf` chains inside a `RUN` block. Hard to lint, test, or diff.
  - Fix: extract each to `scripts/wrappers/*.sh` and `COPY` them in, same pattern as `gcal-wrap.sh`.
  - Files: `Dockerfile`

- [ ] **L2** Runtime env-loading loop duplicated inside Dockerfile `gh`/`git` wrappers
  - The `while IFS='=' read` loop in the baked `gh` and `git` wrappers duplicates `load-runtime-env.sh`
    which is already installed in the image.
  - Fix: replace the inline loop with `source /usr/local/libexec/openclaw-load-runtime-env`.
  - Note: best done together with L1 (extract wrappers to files first).
  - Files: `Dockerfile`

- [ ] **L3** `start-gateway.sh` reads `auth-profiles.json` twice in sequence
  - The auth-profiles node block computes `hasOAuth` then immediately discards the result. A second
    `node -e` block 5 lines later reads the same file again to decide which model to set.
  - Fix: emit the result from the first block and capture it in a bash variable.
  - Files: `scripts/start-gateway.sh`

- [ ] **L4** `start-gateway.sh` double `if [[ -n "${token}" ]]` check
  - The `echo` and `exec` for the token case are in two separate `if` blocks and should be one `if/else`.
  - Files: `scripts/start-gateway.sh`

---

## 💡 Ideas — future capability expansion

These are enhancements, not defects.

- [ ] **A1** Create `~/.openclaw/USER.md` with name, role, time zone, working style
  - The personality system supports this file but `personalities/setup.sh` never creates it.

- [ ] **A2** Lower `AGENT_POLL_INTERVAL_SECS` from 300 → 60 (or add a GitHub webhook trigger)
  - 5-minute lag between creating an issue and the agent picking it up is noticeable in practice.

- [ ] **A3** Increase `AGENT_MAX_CONCURRENCY` from 1 → 2 or 3 for parallel issue processing

- [ ] **A4** Add Brave Search MCP (`@modelcontextprotocol/server-brave-search`) to the gateway image
  - Lets the agent look up docs, error messages, and CVEs without writing raw curl calls.

- [ ] **A5** Add Filesystem MCP (`@modelcontextprotocol/server-filesystem`) pointed at `/workspace`
  - Gives the agent structured read/write/list operations instead of raw shell file manipulation.

- [ ] **A6** Add `make shell` target (`docker compose exec openclaw-gateway bash`) for quick debugging
