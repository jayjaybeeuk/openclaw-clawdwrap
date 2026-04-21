#!/usr/bin/env bash

prompt="${1:-}"

case "$prompt" in
  *Username*) echo "x-access-token" ;;
  *Password*) echo "${GH_TOKEN:-}" ;;
  *) echo "${GH_TOKEN:-}" ;;
esac
