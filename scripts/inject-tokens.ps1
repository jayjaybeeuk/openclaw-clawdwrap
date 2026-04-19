#!/usr/bin/env pwsh
# scripts/inject-tokens.ps1 — Inject runtime secrets from .env into the
# openclaw_run Docker volume (/run/openclaw/env).
#
# Native PowerShell equivalent of scripts/inject-tokens.sh for Windows users
# running docker compose directly without WSL/Git Bash.

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $root ".env"
. (Join-Path $PSScriptRoot "runtime-volume.ps1")

if (-not (Test-Path -LiteralPath $envFile)) {
  throw ".env not found - run .\setup.ps1 first (or setup.sh via WSL)"
}

$runtimeKeys = @(
  "GITHUB_TOKEN",
  "ANTHROPIC_API_KEY",
  "AZURE_DEVOPS_TOKEN",
  "GOOGLE_CLIENT_ID",
  "GOOGLE_CLIENT_SECRET",
  "GOOGLE_REFRESH_TOKEN"
)

$envLines = Get-Content -LiteralPath $envFile
$runtimeLines = New-Object System.Collections.Generic.List[string]

foreach ($key in $runtimeKeys) {
  $line = $envLines | Where-Object { $_ -match "^${key}=" } | Select-Object -First 1
  if (-not $line) { continue }

  $value = $line -replace "^${key}=", ""
  $value = $value -replace "\s+#.*$", ""
  $value = $value.Trim()

  if ($value) {
    [void]$runtimeLines.Add("${key}=${value}")
  }
}

if ($runtimeLines.Count -eq 0) {
  throw "No runtime keys found in .env (checked: $($runtimeKeys -join ', '))"
}

$volume = Get-RuntimeVolumeName -Root $root
$runtimeContent = ($runtimeLines -join "`n") + "`n"

Write-Host ""
Write-Host "Injecting runtime tokens into volume: $volume"

$runtimeContent |
  docker run --rm -i `
    -v "${volume}:/run/openclaw" `
    alpine sh -lc "umask 077; tr -d '\r' > /run/openclaw/env; chown 1000:1000 /run/openclaw/env; chmod 600 /run/openclaw/env"

Write-Host "Tokens written to /run/openclaw/env"
Write-Host ""
Write-Host "Restarting services to pick up new tokens..."

try {
  docker compose --project-directory $root restart clawwrapd openclaw-gateway agent-runner | Out-Null
} catch {
  docker compose --project-directory $root restart clawwrapd openclaw-gateway | Out-Null
}

Write-Host "Done. Validate with: docker compose exec openclaw-gateway sh -lc `"gh api user --jq '.login'`""
