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
COPY scripts/google-auth-lib.sh /usr/local/libexec/google-auth-lib.sh
COPY scripts/start-gateway.sh /usr/local/bin/start-openclaw-gateway
COPY scripts/dashboard-url.sh /usr/local/bin/openclaw-dashboard-url
COPY scripts/wrappers/gh.sh /usr/local/bin/gh
COPY scripts/wrappers/git.sh /usr/local/bin/git
COPY scripts/wrappers/git-askpass-runtime.sh /usr/local/bin/git-askpass-runtime
COPY scripts/wrappers/pinch.sh /usr/local/bin/pinch

# Provide the `pinch` helper expected by this stack's runtime policy.
RUN set -eux; \
  install -d /usr/local/libexec; \
  cp /usr/bin/gh /usr/local/libexec/gh-real; \
  cp /usr/bin/git /usr/local/libexec/git-real; \
  chmod 0755 /usr/local/bin/gh /usr/local/bin/git /usr/local/bin/git-askpass-runtime /usr/local/bin/pinch /usr/local/bin/gcal-wrap /usr/local/bin/gmail-wrap /usr/local/bin/start-openclaw-gateway /usr/local/bin/openclaw-dashboard-url /usr/local/libexec/openclaw-load-runtime-env; \
  ln -sf /usr/local/bin/gcal-wrap /usr/local/bin/gcal; \
  ln -sf /usr/local/bin/gmail-wrap /usr/local/bin/gmail

ENV NODE_ENV=production
ENV SHELL=/bin/bash

RUN mkdir -p /home/node/.openclaw/workspace && chown -R node:node /home/node

USER node

CMD ["openclaw", "gateway", "--allow-unconfigured"]
