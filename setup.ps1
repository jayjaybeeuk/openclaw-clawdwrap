#!/usr/bin/env pwsh
# setup.ps1 — One-click bootstrap for the OpenClaw Docker stack (native Windows/PowerShell).
# Equivalent of setup.sh for users who run PowerShell without WSL.
#
# What it does:
#   1. Creates .env from .env.example if .env is absent or empty.
#   2. Auto-generates random tokens for placeholder sentinel values.
#   3. Reports which secrets still need to be filled in before docker compose up.
#
# Idempotent: re-running never overwrites values you have already set.

$ErrorActionPreference = "Stop"

$root        = $PSScriptRoot
$envFile     = Join-Path $root ".env"
$exampleFile = Join-Path $root ".env.example"

function Write-Step($msg) { Write-Host "`n$msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "  [ERR]  $msg" -ForegroundColor Red }

# ── Step 1: Create .env if missing or empty ──────────────────────────────────────
Write-Step "OpenClaw setup"

if (-not (Test-Path -LiteralPath $exampleFile)) {
  throw ".env.example not found - cannot bootstrap .env"
}

$envExists = (Test-Path -LiteralPath $envFile) -and ((Get-Item -LiteralPath $envFile).Length -gt 0)
if (-not $envExists) {
  Copy-Item -LiteralPath $exampleFile -Destination $envFile
  Write-Host "  • Created .env from .env.example" -ForegroundColor Cyan
} else {
  Write-Ok ".env already exists - skipping copy"
}

# ── Helpers ───────────────────────────────────────────────────────────────────────
. (Join-Path $root "scripts\env-utils.ps1")

function Set-EnvValue {
  param([string]$Key, [string]$Value)
  $lines = Get-Content -LiteralPath $envFile
  $updated = $false
  $result = foreach ($line in $lines) {
    if ($line -match "^${Key}=") { $updated = $true; "${Key}=${Value}" } else { $line }
  }
  if (-not $updated) { $result += "${Key}=${Value}" }
  [System.IO.File]::WriteAllText($envFile, ($result -join "`n") + "`n", [System.Text.UTF8Encoding]::new($false))
}

function New-RandomToken {
  $rng   = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
  $bytes = New-Object byte[] 32
  $rng.GetBytes($bytes)
  $rng.Dispose()
  return -join ($bytes | ForEach-Object { $_.ToString("x2") })
}

# ── Step 2: Auto-generate placeholder random tokens ──────────────────────────────
Write-Step "Generating random tokens"

$sentinel = "replace-with-random-token"
$lines    = Get-Content -LiteralPath $envFile

foreach ($key in @("OPENCLAW_GATEWAY_TOKEN", "PINCHTAB_TOKEN")) {
  $current = Read-EnvValue -Key $key -Lines $lines
  if ($current -eq $sentinel -or [string]::IsNullOrWhiteSpace($current)) {
    Set-EnvValue -Key $key -Value (New-RandomToken)
    Write-Ok "Generated $key"
  } else {
    Write-Ok "$key already set"
  }
}

# ── Step 3: Check required secrets ───────────────────────────────────────────────
Write-Step "Secret checklist"

$missing = 0
$lines   = Get-Content -LiteralPath $envFile  # re-read after token writes

$githubToken = Read-EnvValue -Key "GITHUB_TOKEN" -Lines $lines
if ([string]::IsNullOrWhiteSpace($githubToken)) {
  Write-Err "GITHUB_TOKEN is empty  ->  GitHub PAT with repo + workflow scopes"
  $missing++
} else {
  Write-Ok "GITHUB_TOKEN is set"
}

$llmMode = Read-EnvValue -Key "LLM_AUTH_MODE" -Lines $lines
if (-not $llmMode) { $llmMode = "api_key" }

if ($llmMode -eq "oauth") {
  Write-Ok "LLM_AUTH_MODE=oauth - run 'make login' (via WSL) after docker compose up -d"
} else {
  $openaiKey    = Read-EnvValue -Key "OPENAI_API_KEY"    -Lines $lines
  $anthropicKey = Read-EnvValue -Key "ANTHROPIC_API_KEY" -Lines $lines
  if (-not $openaiKey -and -not $anthropicKey) {
    Write-Err "LLM_AUTH_MODE=api_key but no key set - add OPENAI_API_KEY or ANTHROPIC_API_KEY"
    $missing++
  } elseif ($openaiKey) {
    Write-Ok "OPENAI_API_KEY is set (primary)"
    if ($anthropicKey) { Write-Ok "ANTHROPIC_API_KEY is set (fallback)" }
    else               { Write-Warn "ANTHROPIC_API_KEY not set - no fallback" }
  } else {
    Write-Warn "OPENAI_API_KEY not set - Anthropic will be used as primary"
    Write-Ok   "ANTHROPIC_API_KEY is set"
  }
}

$optionals = @(
  @{ Key = "AZURE_DEVOPS_TOKEN";   Hint = "Azure DevOps PAT (only needed for ADO repos)" },
  @{ Key = "GOOGLE_CLIENT_ID";     Hint = "Google OAuth client ID" },
  @{ Key = "GOOGLE_CLIENT_SECRET"; Hint = "Google OAuth client secret" },
  @{ Key = "GOOGLE_REFRESH_TOKEN"; Hint = "Google OAuth refresh token" }
)
foreach ($o in $optionals) {
  $val = Read-EnvValue -Key $o.Key -Lines $lines
  if ([string]::IsNullOrWhiteSpace($val) -or $val -eq "xxx") {
    Write-Warn "$($o.Key) not set  ->  $($o.Hint) (optional)"
  } else {
    Write-Ok "$($o.Key) is set"
  }
}

# ── Step 4: Summary ───────────────────────────────────────────────────────────────
Write-Step "Summary"

if ($missing -eq 0) {
  Write-Host "`nAll required secrets are set." -ForegroundColor Green
  Write-Host "`nNext steps:"
  Write-Host "  1.  docker compose up -d          - build images and start the stack"
  Write-Host "  2.  .\scripts\inject-tokens.ps1   - sync secrets to the runtime volume"
  if ($llmMode -eq "oauth") {
    Write-Host "  3.  wsl make login                - authenticate LLM providers (one-time)"
    Write-Host "  4.  .\scripts\token-health.ps1   - confirm everything is wired"
  } else {
    Write-Host "  3.  .\scripts\token-health.ps1   - confirm everything is wired"
  }
} else {
  Write-Host "`n$missing required secret(s) still need filling in .env." -ForegroundColor Yellow
  Write-Host "Edit .env, then re-run .\setup.ps1 to verify."
}
Write-Host ""
