#!/usr/bin/env pwsh
# scripts/env-utils.ps1 — Shared .env parsing helpers.
# Dot-source this file; do not execute it directly.

function Read-EnvValue {
  param(
    [string]$Key,
    [string[]]$Lines
  )

  $line = $Lines | Where-Object { $_ -match "^${Key}=" } | Select-Object -First 1
  if (-not $line) { return "" }

  $value = $line -replace "^${Key}=", ""
  $value = $value.TrimEnd("`r")
  $value = $value -replace "\s+#.*$", ""  # strip inline comments
  $value = $value.Trim()

  if ($value.Length -ge 2) {
    if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
        ($value.StartsWith("'") -and $value.EndsWith("'"))) {
      $value = $value.Substring(1, $value.Length - 2)
    }
  }

  return $value
}
