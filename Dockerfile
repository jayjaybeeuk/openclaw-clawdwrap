FROM pinchtab/pinchtab:latest AS pinchtab-cli

FROM node:22-bookworm

ARG OPENCLAW_NPM_SPEC="openclaw@latest"

# Keep the base image self-contained for gateway and CLI usage.
RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    gh \
  ; \
  rm -rf /var/lib/apt/lists/*

RUN npm install -g "${OPENCLAW_NPM_SPEC}"

COPY --from=pinchtab-cli /usr/local/bin/pinchtab /usr/local/bin/pinchtab
COPY scripts/gcal-wrap.sh /usr/local/bin/gcal-wrap
COPY scripts/gmail-wrap.sh /usr/local/bin/gmail-wrap
COPY scripts/load-runtime-env.sh /usr/local/libexec/openclaw-load-runtime-env
COPY scripts/start-gateway.sh /usr/local/bin/start-openclaw-gateway
COPY scripts/dashboard-url.sh /usr/local/bin/openclaw-dashboard-url

# Provide the `pinch` helper expected by this stack's runtime policy.
RUN set -eux; \
  install -d /usr/local/libexec; \
  cp /usr/bin/gh /usr/local/libexec/gh-real; \
  cp /usr/bin/git /usr/local/libexec/git-real; \
  printf '%s\n' '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'if [[ -f /run/openclaw/env ]]; then while IFS='"'"'='"'"' read -r key value || [[ -n "${key:-}" ]]; do [[ -z "${key:-}" || "${key:0:1}" == "#" ]] && continue; value="${value%$'"'"'\r'"'"'}"; export "${key}=${value}"; done < /run/openclaw/env; fi' \
    'if [[ -z "${GH_TOKEN:-}" && -n "${GITHUB_TOKEN:-}" ]]; then export GH_TOKEN="${GITHUB_TOKEN}"; fi' \
    'exec /usr/local/libexec/gh-real "$@"' >/usr/local/bin/gh; \
  printf '%s\n' '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'if [[ -f /run/openclaw/env ]]; then while IFS='"'"'='"'"' read -r key value || [[ -n "${key:-}" ]]; do [[ -z "${key:-}" || "${key:0:1}" == "#" ]] && continue; value="${value%$'"'"'\r'"'"'}"; export "${key}=${value}"; done < /run/openclaw/env; fi' \
    'if [[ -z "${GH_TOKEN:-}" && -n "${GITHUB_TOKEN:-}" ]]; then export GH_TOKEN="${GITHUB_TOKEN}"; fi' \
    'export GIT_ASKPASS="${GIT_ASKPASS:-/usr/local/bin/git-askpass-runtime}"' \
    'export GIT_TERMINAL_PROMPT=0' \
    'exec /usr/local/libexec/git-real "$@"' >/usr/local/bin/git; \
  printf '%s\n' '#!/usr/bin/env bash' \
    'prompt="${1:-}"' \
    'case "$prompt" in' \
    '  *Username*) echo "x-access-token" ;;' \
    '  *Password*) echo "${GH_TOKEN:-}" ;;' \
    '  *) echo "${GH_TOKEN:-}" ;;' \
    'esac' >/usr/local/bin/git-askpass-runtime; \
  printf '%s\n' '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    ': "${PINCHTAB_URL:=http://pinchtab:9867}"' \
    'export PINCHTAB_URL' \
    'if [ -n "${PINCHTAB_TOKEN:-}" ]; then export PINCHTAB_TOKEN; fi' \
    'exec /usr/local/bin/pinchtab "$@"' >/usr/local/bin/pinch; \
  chmod 0755 /usr/local/bin/gh /usr/local/bin/git /usr/local/bin/git-askpass-runtime /usr/local/bin/pinch /usr/local/bin/gcal-wrap /usr/local/bin/gmail-wrap /usr/local/bin/start-openclaw-gateway /usr/local/bin/openclaw-dashboard-url /usr/local/libexec/openclaw-load-runtime-env; \
  ln -sf /usr/local/bin/gcal-wrap /usr/local/bin/gcal; \
  ln -sf /usr/local/bin/gmail-wrap /usr/local/bin/gmail

ENV NODE_ENV=production
ENV SHELL=/bin/bash

RUN mkdir -p /home/node/.openclaw/workspace && chown -R node:node /home/node

USER node

CMD ["openclaw", "gateway", "--allow-unconfigured"]
