#!/usr/bin/env bash

load_runtime_env() {
  local runtime_env="${1:-/run/openclaw/env}"

  if [[ ! -f "$runtime_env" ]]; then
    return
  fi

  while IFS='=' read -r key value || [[ -n "${key:-}" ]]; do
    [[ -z "${key:-}" || "${key:0:1}" == "#" ]] && continue
    value="${value%$'\r'}"
    export "${key}=${value}"
  done < "$runtime_env"
}
