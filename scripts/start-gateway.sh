#!/usr/bin/env bash
set -euo pipefail

bind="${OPENCLAW_GATEWAY_BIND:-lan}"
port="${OPENCLAW_GATEWAY_PORT:-18789}"
token="${OPENCLAW_GATEWAY_TOKEN:-}"

if [[ "${bind}" != "loopback" ]]; then
  origins=("http://127.0.0.1:${port}" "http://localhost:${port}")
  if [[ -n "${OPENCLAW_CONTROL_UI_ALLOWED_ORIGINS:-}" ]]; then
    IFS=',' read -r -a extra_origins <<<"${OPENCLAW_CONTROL_UI_ALLOWED_ORIGINS}"
    for origin in "${extra_origins[@]}"; do
      trimmed="$(printf '%s' "${origin}" | xargs)"
      if [[ -n "${trimmed}" ]]; then
        origins+=("${trimmed}")
      fi
    done
  fi

  origins_json="$(
    node -e 'const values = process.argv.slice(1).map(v => v.trim()).filter(Boolean); process.stdout.write(JSON.stringify([...new Set(values)]));' -- "${origins[@]}"
  )"
  openclaw config set gateway.controlUi.allowedOrigins "${origins_json}"
fi

if [[ -n "${token}" ]]; then
  echo "OpenClaw dashboard URL:"
  openclaw dashboard --no-open || true
fi

if [[ -n "${token}" ]]; then
  exec openclaw gateway --bind "${bind}" --port "${port}" --token "${token}"
fi

exec openclaw gateway --bind "${bind}" --port "${port}"
