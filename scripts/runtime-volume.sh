#!/usr/bin/env bash

get_compose_project_name() {
  local root="${1:?root path required}"
  printf '%s\n' "${COMPOSE_PROJECT_NAME:-$(basename "$root" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/-*$//')}"
}

detect_runtime_volume() {
  local root="${1:?root path required}"
  printf '%s_openclaw_run\n' "$(get_compose_project_name "$root")"
}
