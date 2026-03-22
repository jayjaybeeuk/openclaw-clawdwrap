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
COPY scripts/start-gateway.sh /usr/local/bin/start-openclaw-gateway
COPY scripts/dashboard-url.sh /usr/local/bin/openclaw-dashboard-url

# Provide the `pinch` helper expected by this stack's runtime policy.
RUN set -eux; \
  printf '%s\n' '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    ': "${PINCHTAB_URL:=http://pinchtab:9867}"' \
    'export PINCHTAB_URL' \
    'if [ -n "${PINCHTAB_TOKEN:-}" ]; then export PINCHTAB_TOKEN; fi' \
    'exec /usr/local/bin/pinchtab "$@"' >/usr/local/bin/pinch; \
  chmod 0755 /usr/local/bin/pinch /usr/local/bin/gcal-wrap /usr/local/bin/gmail-wrap /usr/local/bin/start-openclaw-gateway /usr/local/bin/openclaw-dashboard-url; \
  ln -sf /usr/local/bin/gcal-wrap /usr/local/bin/gcal; \
  ln -sf /usr/local/bin/gmail-wrap /usr/local/bin/gmail

ENV NODE_ENV=production
ENV SHELL=/bin/bash

RUN mkdir -p /home/node/.openclaw/workspace && chown -R node:node /home/node

USER node

CMD ["openclaw", "gateway", "--allow-unconfigured"]
