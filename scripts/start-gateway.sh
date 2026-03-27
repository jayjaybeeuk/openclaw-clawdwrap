#!/usr/bin/env bash
set -euo pipefail

bind="${OPENCLAW_GATEWAY_BIND:-lan}"
port="${OPENCLAW_GATEWAY_PORT:-18789}"
token="${OPENCLAW_GATEWAY_TOKEN:-}"

# Ensure gateway runs in local mode (required for browser UI connections).
# Patch the JSON config directly — `openclaw config set gateway.mode` does not
# produce a log line and appears to be silently ignored for this key.
node - <<'EOF'
const fs = require('fs');
const p = '/home/node/.openclaw/openclaw.json';
let cfg = {};
try { cfg = JSON.parse(fs.readFileSync(p, 'utf8')); } catch (_) {
  fs.mkdirSync('/home/node/.openclaw', { recursive: true });
}
cfg.gateway = cfg.gateway || {};
cfg.gateway.mode = 'local';
fs.writeFileSync(p, JSON.stringify(cfg, null, 2));
EOF

# Merge API key profiles into auth-profiles.json.
# Skipped entirely when LLM_AUTH_MODE=oauth — OAuth profiles managed via `make login`.
# OAuth/token profiles are always preserved — never wiped.
# Managed API key entries (openai-1, anthropic-1) are added only if missing.
node - <<AUTHEOF
const fs = require('fs');
const dir = '/home/node/.openclaw/agents/main/agent';
const p   = dir + '/auth-profiles.json';
fs.mkdirSync(dir, { recursive: true });
let store = { version: 1, profiles: {} };
try { store = JSON.parse(fs.readFileSync(p, 'utf8')); } catch (_) {}
store.profiles = store.profiles || {};

const oauthMode = process.env.LLM_AUTH_MODE === 'oauth';

// Check whether any OAuth/token profiles exist (added via `make login`).
const hasOAuth = Object.values(store.profiles).some(
  v => v.mode === 'oauth' || v.type === 'oauth' || v.type === 'token'
);

if (oauthMode || hasOAuth) {
  // OAuth mode: profiles managed via `make login` — never inject API keys.
  if (Object.keys(store.profiles).length > 0) {
    console.log('auth-profiles.json: OAuth mode — preserving existing profiles');
  } else {
    console.error('auth-profiles.json: OAuth mode but no profiles found — run: make login');
  }
} else {
  // API key mode: add entries only when missing — never overwrite.
  if (process.env.OPENAI_API_KEY && !store.profiles['openai-1']) {
    store.profiles['openai-1'] = { type: 'api_key', provider: 'openai', key: process.env.OPENAI_API_KEY };
    console.log('auth-profiles.json: openai-1 set (api_key)');
  }
  if (process.env.ANTHROPIC_API_KEY && !store.profiles['anthropic-1']) {
    store.profiles['anthropic-1'] = { type: 'api_key', provider: 'anthropic', key: process.env.ANTHROPIC_API_KEY };
    console.log('auth-profiles.json: anthropic-1 set (api_key)');
  }
}

// Clear lastGood/usageStats so OpenClaw doesn't override the profile order
delete store.lastGood;
delete store.usageStats;

if (Object.keys(store.profiles).length > 0) {
  fs.writeFileSync(p, JSON.stringify(store, null, 2));
} else {
  console.error('auth-profiles.json: WARNING — no auth profiles found. Run: make login');
}
AUTHEOF

# Set default model from env keys only if no OAuth profile exists.
# `make login` sets the model via --set-default; don't clobber it on restart.
_has_oauth=$(node -e "
  try {
    const s = require('fs').readFileSync('/home/node/.openclaw/agents/main/agent/auth-profiles.json','utf8');
    const p = JSON.parse(s).profiles || {};
    const has = Object.values(p).some(v => v.mode === 'oauth' || v.type === 'oauth' || v.type === 'token');
    process.stdout.write(has ? 'yes' : 'no');
  } catch(_) { process.stdout.write('no'); }
" 2>/dev/null)
if [[ "${_has_oauth}" != "yes" ]]; then
  if [[ -n "${OPENAI_API_KEY:-}" ]]; then
    openclaw models set openai/gpt-4o 2>/dev/null || true
  elif [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    openclaw models set anthropic/claude-opus-4-6 2>/dev/null || true
  fi
fi
unset _has_oauth

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
  echo "Dashboard URL: http://127.0.0.1:${port}/#token=${token}"
fi

if [[ -n "${token}" ]]; then
  exec openclaw gateway run --auth token --bind "${bind}" --port "${port}" --token "${token}"
fi

exec openclaw gateway run --auth none --bind "${bind}" --port "${port}"
