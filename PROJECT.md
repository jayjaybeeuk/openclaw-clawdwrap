---
project: autonomous-coding-agent
status: in-progress
version: "0.1.0"
created: 2026-03-25
updated: 2026-03-25
owner: jayjaybeeuk
repo: jayjaybeeuk/openclaw-clawdwrap
---

# Project: Autonomous Coding Agent

Extend the OpenClaw Docker stack so it can act as a fully autonomous coding agent.
Given a GitHub or Azure DevOps repository URL, the agent will:

1. Fetch open issues from the target repo
2. Triage and claim a suitable issue
3. Clone the repo into an isolated workspace
4. Run Claude Code (via `claude` CLI + `ANTHROPIC_API_KEY`) inside that workspace with the issue as context
5. Commit the resulting changes to a feature branch (`agent/<issue-number>-<slug>`)
6. Push the branch and open a PR back to the origin repo
7. Clean up the workspace and write an audit log entry

Everything runs inside Docker; `git` and `gh` remain gated through `claw-wrap` so the existing security policy (no direct push to `main`/`master`, no force-push, token injection model) is preserved throughout.

---

## Architecture

```
  HOST
  ┌────────────────────────────────────────────────────────────────┐
  │  docker-compose                                                │
  │                                                                │
  │  ┌─────────────────┐   unix socket   ┌──────────────────────┐ │
  │  │  clawwrapd       │◄───────────────►│  openclaw-gateway    │ │
  │  │  (claw-wrap      │                 │  (OpenClaw + gh +    │ │
  │  │   daemon)        │                 │   git + PinchTab)    │ │
  │  │                  │                 └──────────────────────┘ │
  │  │  wrappers.yml    │   unix socket   ┌──────────────────────┐ │
  │  │  policy enforced │◄───────────────►│  agent-runner   NEW  │ │
  │  │                  │                 │  (Node 22 + tsx +    │ │
  │  │  credentials:    │                 │   @anthropic-ai/sdk  │ │
  │  │  - GITHUB_TOKEN  │                 │   azure-devops-api   │ │
  │  │  - ANTHROPIC_KEY │                 │   claude CLI)        │ │
  │  │  - AZURE_PAT     │                 └──────────┬───────────┘ │
  │  └─────────────────┘                            │             │
  │                                                 │             │
  │  volumes:                                       │             │
  │  ┌──────────────┐  ┌──────────────────────────┐ │             │
  │  │ openclaw_run │  │ repos  NEW               │◄┘             │
  │  │ (auth token  │  │ /repos/<uuid>/            │               │
  │  │  + socket)   │  │  one dir per issue        │               │
  │  └──────────────┘  └──────────────────────────┘               │
  │                                                                │
  │  ┌──────────────────────┐                                      │
  │  │  pinchtab            │  (unchanged)                         │
  │  └──────────────────────┘                                      │
  └────────────────────────────────────────────────────────────────┘

  EXTERNAL
  ┌──────────────────────┐   ┌─────────────────────────────┐
  │  GitHub / GitHub MCP │   │  Azure DevOps REST API      │
  │  (issues + PRs)      │   │  (issues + PRs)             │
  └──────────────────────┘   └─────────────────────────────┘
```

---

## Status Key

| Badge | Meaning |
|---|---|
| `[ ]` | todo — not started |
| `[~]` | in-progress |
| `[x]` | done |
| `[!]` | blocked — dependency unmet |

## Category Key

`setup` `docker` `skill` `script` `mcp` `permissions` `test`

---

## Phase 1 — Credentials & Policy

> Add the new secrets and confirm existing policy covers agent workflows.

| ID | Status | Cat | Task | Depends |
|---|---|---|---|---|
| P1-001 | `[ ]` | `setup` | Add `ANTHROPIC_API_KEY` to `.env.example` | — |
| P1-002 | `[ ]` | `setup` | Add `AZURE_DEVOPS_TOKEN` to `.env.example` | — |
| P1-003 | `[ ]` | `setup` | Add `AZURE_DEVOPS_ORG` and `AZURE_DEVOPS_PROJECT` to `.env.example` | — |
| P1-004 | `[ ]` | `permissions` | Add `anthropic-api-key` credential to `wrappers.yml` (source: `env:ANTHROPIC_API_KEY`) | P1-001 |
| P1-005 | `[ ]` | `permissions` | Add `azure-devops-token` credential to `wrappers.yml` (source: `env:AZURE_DEVOPS_TOKEN`) | P1-002 |
| P1-006 | `[ ]` | `permissions` | Verify `gh pr create`, `gh issue list`, `gh issue view` are NOT blocked in `wrappers.yml`; add explicit allow-note comment | — |
| P1-007 | `[ ]` | `docker` | Extend `openclaw_run` injection script in `AGENTS.md` to also write `ANTHROPIC_API_KEY` and `AZURE_DEVOPS_TOKEN` | P1-001, P1-002 |

### Notes
- Keep the same injection model: secrets written to `/run/openclaw/env` via the volume, never in repo files.
- `ANTHROPIC_API_KEY` must reach `agent-runner` at runtime; `AZURE_DEVOPS_TOKEN` is optional if only targeting GitHub.
- The `claw-wrap` daemon reads `wrappers.yml` at startup; restart `clawwrapd` after changes.

---

## Phase 2 — Docker Changes

> New `agent-runner` service + `repos` workspace volume.

| ID | Status | Cat | Task | Depends |
|---|---|---|---|---|
| P2-001 | `[ ]` | `docker` | Create `Dockerfile.agent-runner` | — |
| P2-002 | `[ ]` | `docker` | Add `agent-runner` service to `docker-compose.yml` | P2-001 |
| P2-003 | `[ ]` | `docker` | Declare `repos` named volume in `docker-compose.yml` | — |
| P2-004 | `[ ]` | `docker` | Add resource limits (`cpus`, `memory`) to `agent-runner` | P2-002 |
| P2-005 | `[ ]` | `docker` | Document security posture for `agent-runner` (no `privileged`, no `seccomp:unconfined`, no host-network) | P2-002 |
| P2-006 | `[ ]` | `docker` | Add `AGENT_MAX_CONCURRENCY`, `AGENT_DRY_RUN`, `AGENT_POLL_INTERVAL_SECS` env vars to service definition | P2-002 |

### `Dockerfile.agent-runner` specification

```dockerfile
FROM node:22-bookworm

# Build stage: same claw-wrap binary as Dockerfile.openclaw-tools
COPY --from=openclaw/clawwrapd:local /usr/local/bin/claw-wrap /usr/local/bin/claw-wrap
COPY --from=openclaw/clawwrapd:local /usr/local/libexec/gh     /usr/local/libexec/gh
COPY --from=openclaw/clawwrapd:local /usr/local/libexec/git    /usr/local/libexec/git
COPY --from=openclaw/clawwrapd:local /usr/local/bin/git-askpass-claw /usr/local/bin/git-askpass-claw

# Route gh/git through claw-wrap (same symlink pattern)
RUN ln -sf /usr/local/bin/claw-wrap /usr/local/bin/gh && \
    ln -sf /usr/local/bin/claw-wrap /usr/local/bin/git

# TypeScript runtime
RUN npm install -g tsx typescript

# Claude Code CLI (requires ANTHROPIC_API_KEY at runtime)
RUN npm install -g @anthropic-ai/claude-code

# Agent package (built in next phase)
WORKDIR /agent
COPY agent/package*.json ./
RUN npm ci
COPY agent/ ./
RUN npm run build

ENV GIT_ASKPASS=/usr/local/bin/git-askpass-claw
ENV SHELL=/bin/bash
USER node
CMD ["node", "dist/index.js"]
```

### `docker-compose.yml` addition (agent-runner service sketch)

```yaml
agent-runner:
  image: openclaw/agent-runner:local
  build:
    context: .
    dockerfile: Dockerfile.agent-runner
  depends_on:
    - clawwrapd
  environment:
    HOME: /home/node
    SHELL: /bin/bash
    ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY}
    AZURE_DEVOPS_TOKEN: ${AZURE_DEVOPS_TOKEN:-}
    AZURE_DEVOPS_ORG: ${AZURE_DEVOPS_ORG:-}
    AZURE_DEVOPS_PROJECT: ${AZURE_DEVOPS_PROJECT:-}
    GIT_AUTHOR_NAME: ${GIT_AUTHOR_NAME:-James Bolton}
    GIT_AUTHOR_EMAIL: ${GIT_AUTHOR_EMAIL:-jayjaybeeuk@gmail.com}
    GIT_COMMITTER_NAME: ${GIT_COMMITTER_NAME:-James Bolton}
    GIT_COMMITTER_EMAIL: ${GIT_COMMITTER_EMAIL:-jayjaybeeuk@gmail.com}
    AGENT_MAX_CONCURRENCY: ${AGENT_MAX_CONCURRENCY:-1}
    AGENT_DRY_RUN: ${AGENT_DRY_RUN:-false}
    AGENT_POLL_INTERVAL_SECS: ${AGENT_POLL_INTERVAL_SECS:-300}
  volumes:
    - openclaw_run:/run/openclaw          # claw-wrap socket + injected token
    - repos:/repos                        # per-issue workspace dirs
    - ${OPENCLAW_CONFIG_DIR}:/home/node/.openclaw
  deploy:
    resources:
      limits:
        cpus: "2.0"
        memory: 4G
  restart: unless-stopped
  init: true
```

### Docker implications summary

- **No Docker-in-Docker needed** — `agent-runner` talks to `clawwrapd` over the Unix socket in `openclaw_run`; all `git`/`gh` calls are mediated by `claw-wrap` exactly as in `openclaw-gateway`.
- **No `seccomp:unconfined`** — that is only needed for Chrome (PinchTab). `agent-runner` has no browser.
- **No `privileged` flag** — not needed; agent only writes to its own `/repos` volume.
- **`repos` volume** — mount as read-write for `agent-runner` only. Other services do not need it.
- **Build order** — `Dockerfile.agent-runner` copies binaries from the `clawwrapd` image; ensure `clawwrapd` builds first (`docker compose build clawwrapd agent-runner`).
- **Ephemeral workspaces** — each issue run creates `/repos/<uuid>/`; the orchestrator deletes it on completion or failure. Volume does not grow unbounded.

---

## Phase 3 — TypeScript Agent Core

> The `agent/` Node.js package that runs inside `agent-runner`.

| ID | Status | Cat | Task | Depends |
|---|---|---|---|---|
| P3-001 | `[ ]` | `script` | Scaffold `agent/` — `package.json`, `tsconfig.json`, `src/index.ts` | — |
| P3-002 | `[ ]` | `script` | `src/RepoManager.ts` — clone/pull, branch creation, cleanup | P3-001 |
| P3-003 | `[ ]` | `script` | `src/IssueIngester.ts` — unified `Issue[]` from GitHub or Azure DevOps | P3-001 |
| P3-004 | `[ ]` | `script` | `src/IssueTriage.ts` — label/complexity scoring, skip-list | P3-003 |
| P3-005 | `[ ]` | `script` | `src/ClaudeRunner.ts` — spawn `claude` CLI in repo dir, capture output | P3-002 |
| P3-006 | `[ ]` | `script` | `src/PRCreator.ts` — commit, push branch, `gh pr create` | P3-002, P3-005 |
| P3-007 | `[ ]` | `script` | `src/AgentOrchestrator.ts` — main loop, claim locking, audit log | P3-002, P3-003, P3-004, P3-005, P3-006 |

### Key design decisions

**IssueIngester — provider abstraction**

```typescript
interface Issue {
  id: string;           // "123" (GitHub) or "456" (ADO work item)
  title: string;
  body: string;
  labels: string[];
  provider: "github" | "azure";
  repoUrl: string;
  cloneUrl: string;
}
```

- GitHub: `gh issue list --json number,title,body,labels` (uses wrapped `gh`)
- Azure DevOps: `azure-devops-node-api` (`WorkItemTrackingApi.getWorkItems`) with `AZURE_DEVOPS_TOKEN`

**ClaudeRunner — how it invokes Claude Code**

```typescript
// Runs:  claude --print "<issue body + instructions>" inside the cloned repo
// Uses:  ANTHROPIC_API_KEY from env (already injected via openclaw_run)
// Flags: --print for non-interactive; --allowedTools Bash,Edit,Write,Read
spawnSync("claude", [
  "--print",
  "--allowedTools", "Bash,Edit,Write,Read,Glob,Grep",
  prompt
], { cwd: workspace, env: process.env, stdio: "inherit" });
```

**AgentOrchestrator — claim locking**

To prevent two concurrent agent instances processing the same issue:
1. Before processing: add label `agent:claimed` + comment `🤖 Agent claimed this issue`
2. `IssueIngester` filters out any issue already labelled `agent:claimed` or `agent:done`
3. On PR creation: add label `agent:done`, remove `agent:claimed`
4. On failure: remove `agent:claimed`, add `agent:failed` + failure comment

**Audit log format** (`/repos/agent.log` — JSON Lines):

```json
{"ts":"2026-03-25T10:00:00Z","level":"info","event":"issue_claimed","issueId":"42","repo":"owner/repo"}
{"ts":"2026-03-25T10:05:00Z","level":"info","event":"pr_created","prUrl":"https://github.com/owner/repo/pull/99","issueId":"42"}
```

---

## Phase 4 — OpenClaw Skills

> Discrete skills callable from the OpenClaw gateway (e.g. `openclaw run skill repo-clone`).
> Skills live in `~/.openclaw/skills/` (or `OPENCLAW_CONFIG_DIR/skills/`).

| ID | Status | Cat | Task | Depends |
|---|---|---|---|---|
| P4-001 | `[ ]` | `skill` | `skills/repo-clone.sh` — clone or pull a repo into `/repos/<taskId>/` | P3-002 |
| P4-002 | `[ ]` | `skill` | `skills/issue-list.sh` — list open, unclaimed issues from GitHub or Azure | P3-003 |
| P4-003 | `[ ]` | `skill` | `skills/issue-claim.sh` — apply `agent:claimed` label + comment | P3-007 |
| P4-004 | `[ ]` | `skill` | `skills/issue-process.sh` — run ClaudeRunner on a claimed issue | P3-005 |
| P4-005 | `[ ]` | `skill` | `skills/pr-create.sh` — commit, push, open PR; print PR URL | P3-006 |
| P4-006 | `[ ]` | `skill` | `skills/agent-run.sh` — top-level orchestration; calls all the above in order | P4-001–P4-005 |

### Skill interface convention

Each skill is an executable script that:
- Accepts named env vars (`REPO_URL`, `ISSUE_ID`, `PROVIDER`, `TASK_ID`, etc.)
- Prints structured output (JSON or plain text) to stdout
- Returns 0 on success, non-zero on failure
- Is idempotent where possible

Example invocation via OpenClaw gateway:

```bash
REPO_URL=https://github.com/owner/repo \
PROVIDER=github \
openclaw run skill agent-run
```

### Skills directory layout

```
agent/
  skills/
    repo-clone.sh
    issue-list.sh
    issue-claim.sh
    issue-process.sh
    pr-create.sh
    agent-run.sh
```

These are mounted into `agent-runner` and also copied to `openclaw-gateway`'s skills dir so they can be triggered from the Control UI or via MCP tool calls.

---

## Phase 5 — MCP Servers

> MCP servers extend what the OpenClaw gateway's AI can see and act on.

| ID | Status | Cat | Task | Depends |
|---|---|---|---|---|
| P5-001 | `[ ]` | `mcp` | Document existing GitHub MCP (`mcp__github__*`) in `AGENTS.md` — already usable for issue read/write and PR creation | — |
| P5-002 | `[ ]` | `mcp` | Add **Azure DevOps MCP** server config | P1-002, P1-003 |
| P5-003 | `[ ]` | `mcp` | Add **filesystem MCP** server pointing at `/repos` volume | P2-003 |
| P5-004 | `[ ]` | `mcp` | Document MCP config file location and format in `AGENTS.md` | P5-001–P5-003 |

### P5-002 — Azure DevOps MCP

Recommended package: `@tiberriver256/mcp-server-azure-devops` (npm)

Add to `~/.openclaw/mcp.json` (or however OpenClaw loads MCP servers):

```json
{
  "mcpServers": {
    "azure-devops": {
      "command": "npx",
      "args": ["-y", "@tiberriver256/mcp-server-azure-devops"],
      "env": {
        "AZURE_DEVOPS_ORG": "${AZURE_DEVOPS_ORG}",
        "AZURE_DEVOPS_PROJECT": "${AZURE_DEVOPS_PROJECT}",
        "AZURE_DEVOPS_TOKEN": "${AZURE_DEVOPS_TOKEN}"
      }
    }
  }
}
```

Alternative: write a thin TypeScript wrapper using `azure-devops-node-api` that exposes the same `list_issues` / `create_pr` surface as the GitHub MCP tools. This gives full control over the schema.

### P5-003 — Filesystem MCP

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/repos"]
    }
  }
}
```

Allows the gateway AI to read files in cloned repos (e.g. to review diffs before approving a PR).

---

## Phase 6 — wrappers.yml Updates

> Policy additions for Azure DevOps CLI and explicit audit of existing `gh` policy.

| ID | Status | Cat | Task | Depends |
|---|---|---|---|---|
| P6-001 | `[ ]` | `permissions` | Add `azure-devops-cli` tool entry (uses `az devops` or `azure-devops-node-api` CLI wrapper) with `AZURE_DEVOPS_TOKEN` injected and destructive operations blocked | P1-005 |
| P6-002 | `[ ]` | `permissions` | Confirm `gh pr create` and `gh issue list/view/comment` are permitted; add inline policy comment | — |
| P6-003 | `[ ]` | `permissions` | Add `anthropic-api-key` credential entry to `wrappers.yml` (for injection into `agent-runner` via `openclaw_run`) | P1-004 |
| P6-004 | `[ ]` | `permissions` | Document branch naming convention in `AGENTS.md`: agent PRs must use `agent/<issue-number>-<slug>` | — |

### Proposed `wrappers.yml` additions

```yaml
credentials:
  # ... existing entries ...
  anthropic-api-key:
    source: env:ANTHROPIC_API_KEY
  azure-devops-token:
    source: env:AZURE_DEVOPS_TOKEN

tools:
  # ... existing tools ...
  az:
    binary: /usr/bin/az
    env:
      AZURE_DEVOPS_EXT_PAT: azure-devops-token
    blocked_args:
      - pattern: "devops\\s+project\\s+delete"
        match: command
        message: "Azure DevOps project deletion is blocked"
      - pattern: "devops\\s+repo\\s+delete"
        match: command
        message: "Azure DevOps repo deletion is blocked"
      - pattern: "pipelines?\\s+(delete|destroy)"
        match: command
        message: "Pipeline deletion is blocked"
```

---

## Phase 7 — Security & Hardening

> Ensure the agent cannot be weaponised, cannot leak secrets, and cannot consume unbounded resources.

| ID | Status | Cat | Task | Depends |
|---|---|---|---|---|
| P7-001 | `[ ]` | `setup` | Workspace isolation — each issue gets `/repos/<uuid>/`; AgentOrchestrator deletes it on success or failure | P3-007 |
| P7-002 | `[ ]` | `permissions` | Claim locking — `agent:claimed` label applied before any work begins; prevents double-processing by concurrent agent instances | P3-007 |
| P7-003 | `[ ]` | `setup` | `AGENT_MAX_CONCURRENCY` env var caps parallel runs; orchestrator uses a semaphore | P3-007 |
| P7-004 | `[ ]` | `setup` | Audit log — structured JSON Lines to `/repos/agent.log`; mount a host path for external inspection | P3-007 |
| P7-005 | `[ ]` | `docker` | `agent-runner` must not have `privileged: true`, `network_mode: host`, or `seccomp: unconfined` | P2-002 |
| P7-006 | `[ ]` | `permissions` | `claude` CLI runs with `--allowedTools` restricted to `Bash,Edit,Write,Read,Glob,Grep` — no MCP tools, no web fetch inside the coding run | P3-005 |
| P7-007 | `[ ]` | `setup` | `AGENT_DRY_RUN=true` mode — full pipeline runs but `git push` and `gh pr create` are skipped; output is logged | P3-007 |
| P7-008 | `[ ]` | `setup` | Issue skip-list — issues labelled `wontfix`, `duplicate`, `invalid`, `agent:failed` (3+ times) are ignored | P3-004 |

---

## Phase 8 — Testing & Validation

| ID | Status | Cat | Task | Depends |
|---|---|---|---|---|
| P8-001 | `[ ]` | `test` | Create `test-fixtures/sample-issue.json` — a realistic issue payload for unit tests | P3-003 |
| P8-002 | `[ ]` | `test` | Unit tests for `IssueTriage.ts` — assert correct scoring/skipping with fixture data | P8-001 |
| P8-003 | `[ ]` | `test` | Integration test script — `AGENT_DRY_RUN=true` run against a public test repo; assert workspace created, branch exists, no PR opened | P7-007 |
| P8-004 | `[ ]` | `test` | Run `docker compose exec clawwrapd sh -lc "claw-wrap check"` after all docker changes to confirm wrapper policy still valid | P2-002, P6-001 |
| P8-005 | `[ ]` | `test` | End-to-end smoke test — use `AGENT_DRY_RUN=false` against a private test repo; verify PR appears in GitHub | P8-003 |

---

## Dependency Graph (simplified)

```
P1 (credentials) ──► P2 (docker) ──► P3 (TS core) ──► P4 (skills)
                                            │
                                            ├──────────► P5 (MCPs)
                                            │
P6 (wrappers.yml) ◄─────────────────────────┘
                                            │
P7 (hardening) ◄────────────────────────────┘
                                            │
P8 (tests) ◄────────────────────────────────┘
```

Critical path: **P1 → P2 → P3-001 through P3-007 → P7-001 through P7-007 → P8-003**

---

## Environment Variables Reference

| Variable | Where set | Purpose |
|---|---|---|
| `ANTHROPIC_API_KEY` | `openclaw_run` volume | Authenticates `claude` CLI + `@anthropic-ai/sdk` |
| `AZURE_DEVOPS_TOKEN` | `openclaw_run` volume | PAT for Azure DevOps REST API |
| `AZURE_DEVOPS_ORG` | `.env` / docker env | ADO organisation slug |
| `AZURE_DEVOPS_PROJECT` | `.env` / docker env | ADO project name |
| `AGENT_MAX_CONCURRENCY` | docker env | Max parallel issue runs (default: `1`) |
| `AGENT_DRY_RUN` | docker env | Skip push + PR creation (default: `false`) |
| `AGENT_POLL_INTERVAL_SECS` | docker env | How often to poll for new issues (default: `300`) |
| `GITHUB_TOKEN` | `openclaw_run` volume | Existing; used by `gh` via `claw-wrap` |

---

## Files to Create / Modify

| Path | Action | Phase |
|---|---|---|
| `.env.example` | Add `ANTHROPIC_API_KEY`, `AZURE_DEVOPS_TOKEN`, `AZURE_DEVOPS_ORG`, `AZURE_DEVOPS_PROJECT`, `AGENT_*` vars | P1 |
| `wrappers.yml` | Add `anthropic-api-key`, `azure-devops-token` credentials; add `az` tool entry | P1, P6 |
| `docker-compose.yml` | Add `agent-runner` service + `repos` volume | P2 |
| `Dockerfile.agent-runner` | **Create** — Node 22 + tsx + claude CLI + claw-wrap binaries | P2 |
| `agent/package.json` | **Create** | P3 |
| `agent/tsconfig.json` | **Create** | P3 |
| `agent/src/index.ts` | **Create** — entrypoint, starts AgentOrchestrator | P3 |
| `agent/src/RepoManager.ts` | **Create** | P3 |
| `agent/src/IssueIngester.ts` | **Create** | P3 |
| `agent/src/IssueTriage.ts` | **Create** | P3 |
| `agent/src/ClaudeRunner.ts` | **Create** | P3 |
| `agent/src/PRCreator.ts` | **Create** | P3 |
| `agent/src/AgentOrchestrator.ts` | **Create** | P3 |
| `agent/skills/repo-clone.sh` | **Create** | P4 |
| `agent/skills/issue-list.sh` | **Create** | P4 |
| `agent/skills/issue-claim.sh` | **Create** | P4 |
| `agent/skills/issue-process.sh` | **Create** | P4 |
| `agent/skills/pr-create.sh` | **Create** | P4 |
| `agent/skills/agent-run.sh` | **Create** | P4 |
| `AGENTS.md` | Add MCP config docs, agent branch naming policy, new env vars | P5, P6 |
| `test-fixtures/sample-issue.json` | **Create** | P8 |

---

## Maestro Task Summary

```
Total tasks:  37
[ ] todo:     37
[~] in-progress: 0
[x] done:     0
[!] blocked:  0
```

*This document is the living project plan. Update task statuses as work progresses.
Compatible with Maestro workflow orchestration — each task row maps to a Maestro task node.*
