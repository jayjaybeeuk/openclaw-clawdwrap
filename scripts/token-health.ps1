#!/usr/bin/env pwsh
# scripts/token-health.ps1 — Check auth/token health for GitHub, Google, and LLM providers.

$ErrorActionPreference = "Stop"
if ($null -ne (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue)) {
  $PSNativeCommandUseErrorActionPreference = $false
}

$root = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $root ".env"
$failed = 0
$warned = 0
. (Join-Path $PSScriptRoot "runtime-volume.ps1")

function Write-Ok($Message) { Write-Host "  [OK] $Message" -ForegroundColor Green }
function Write-WarnLine($Message) { Write-Host "  [WARN] $Message" -ForegroundColor Yellow }
function Write-ErrLine($Message) { Write-Host "  [ERR] $Message" -ForegroundColor Red }

function Read-EnvValue {
  param(
    [string]$Key,
    [string[]]$Lines
  )

  $line = $Lines | Where-Object { $_ -match "^${Key}=" } | Select-Object -First 1
  if (-not $line) { return "" }

  $value = $line -replace "^${Key}=", ""
  $value = $value.Trim()

  if ($value.Length -ge 2) {
    if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
      $value = $value.Substring(1, $value.Length - 2)
    }
  }

  return $value.Trim()
}

function Invoke-CmdCapture {
  param([string]$Command)

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = "cmd.exe"
  $psi.Arguments = "/d /c $Command"
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true

  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $psi
  [void]$process.Start()
  $stdout = $process.StandardOutput.ReadToEnd()
  $null = $process.StandardError.ReadToEnd()
  $process.WaitForExit()

  return [PSCustomObject]@{
    ExitCode = $process.ExitCode
    Output = @($stdout -split "`r?`n" | Where-Object { $_ -ne "" })
  }
}

function Test-GatewayRunning {
  $services = (Invoke-CmdCapture "docker compose --project-directory `"$root`" ps --status running --services").Output
  return ($services -contains "openclaw-gateway")
}

function Get-AuthProfilesStatus {
  param([string]$ConfigDir)

  if (-not $ConfigDir) { return "" }
  $authFile = Join-Path $ConfigDir "agents\main\agent\auth-profiles.json"
  if (-not (Test-Path -LiteralPath $authFile)) { return "" }

  try {
    $json = Get-Content -LiteralPath $authFile -Raw | ConvertFrom-Json
    $profiles = @()
    if ($json.profiles) {
      $profiles = $json.profiles.PSObject.Properties | ForEach-Object { $_.Value }
    }

    if ($profiles | Where-Object { $_.mode -eq "oauth" -or $_.type -eq "oauth" -or $_.type -eq "token" }) {
      return "oauth"
    }
    if ($profiles | Where-Object { $_.type -eq "api_key" }) {
      return "api_key"
    }
  } catch {
    return ""
  }

  return ""
}

function Test-RuntimeEnvKey {
  param(
    [string]$Volume,
    [string]$Key
  )

  $result = Invoke-CmdCapture "docker run --rm -v ${Volume}:/run/openclaw alpine sh -lc `"grep -q '^${Key}=' /run/openclaw/env`""
  return ($result.ExitCode -eq 0)
}

Write-Host ""
Write-Host "Token Health Check" -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $envFile)) {
  throw ".env not found - run ./setup.sh first"
}

$envLines = Get-Content -LiteralPath $envFile
$githubToken = Read-EnvValue -Key "GITHUB_TOKEN" -Lines $envLines
$googleClientId = Read-EnvValue -Key "GOOGLE_CLIENT_ID" -Lines $envLines
$googleClientSecret = Read-EnvValue -Key "GOOGLE_CLIENT_SECRET" -Lines $envLines
$googleRefreshToken = Read-EnvValue -Key "GOOGLE_REFRESH_TOKEN" -Lines $envLines
$llmAuthMode = Read-EnvValue -Key "LLM_AUTH_MODE" -Lines $envLines
if (-not $llmAuthMode) { $llmAuthMode = "api_key" }

Write-Host ""
Write-Host "Config" -ForegroundColor Cyan

if ($githubToken) {
  Write-Ok "GITHUB_TOKEN present in .env"
} else {
  Write-ErrLine "GITHUB_TOKEN missing in .env - GitHub calls will fail"
  $failed++
}

if ($googleClientId -and $googleClientSecret -and $googleRefreshToken) {
  Write-Ok "Google OAuth client + refresh token present in .env"
} elseif ($googleClientId -or $googleClientSecret -or $googleRefreshToken) {
  Write-WarnLine "Google OAuth config is partial - update GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET / GOOGLE_REFRESH_TOKEN"
  $warned++
} else {
  Write-WarnLine "Google OAuth config not set - gcal/gmail will not work"
  $warned++
}

if ($llmAuthMode -eq "oauth") {
  $configDir = Read-EnvValue -Key "OPENCLAW_CONFIG_DIR" -Lines $envLines
  switch (Get-AuthProfilesStatus -ConfigDir $configDir) {
    "oauth" { Write-Ok "LLM_AUTH_MODE=oauth and OAuth profiles exist" }
    "api_key" {
      Write-WarnLine "LLM_AUTH_MODE=oauth but only API-key profiles were found - run make login"
      $warned++
    }
    default {
      Write-WarnLine "LLM_AUTH_MODE=oauth but no OAuth profiles were found - run make login"
      $warned++
    }
  }
} else {
  $openaiKey = Read-EnvValue -Key "OPENAI_API_KEY" -Lines $envLines
  $anthropicKey = Read-EnvValue -Key "ANTHROPIC_API_KEY" -Lines $envLines
  if ($openaiKey -or $anthropicKey) {
    Write-Ok "LLM_AUTH_MODE=api_key and at least one provider key is present"
  } else {
    Write-ErrLine "LLM_AUTH_MODE=api_key but no OPENAI_API_KEY or ANTHROPIC_API_KEY is set"
    $failed++
  }
}

Write-Host ""
Write-Host "Runtime Volume" -ForegroundColor Cyan

$dockerInfo = Invoke-CmdCapture "docker info >nul"
if ($dockerInfo.ExitCode -eq 0) {
  $runtimeVolume = Get-RuntimeVolumeName -Root $root
  $volumeInspect = Invoke-CmdCapture "docker volume inspect $runtimeVolume >nul"
  if ($volumeInspect.ExitCode -eq 0) {
    Write-Ok "Runtime volume exists: $runtimeVolume"

    if (Test-RuntimeEnvKey -Volume $runtimeVolume -Key "GITHUB_TOKEN") {
      Write-Ok "Runtime env contains GITHUB_TOKEN"
    } else {
      Write-WarnLine "Runtime env is missing GITHUB_TOKEN - run make inject-tokens or .\scripts\inject-tokens.ps1"
      $warned++
    }

    if ($googleRefreshToken) {
      if ((Test-RuntimeEnvKey -Volume $runtimeVolume -Key "GOOGLE_REFRESH_TOKEN") -and (Test-RuntimeEnvKey -Volume $runtimeVolume -Key "GOOGLE_CLIENT_ID")) {
        Write-Ok "Runtime env contains Google OAuth credentials"
      } else {
        Write-WarnLine "Runtime env is missing Google OAuth credentials - re-run token injection"
        $warned++
      }
    }
  } else {
    Write-WarnLine "Runtime volume not found yet ($runtimeVolume) - start the stack first"
    $warned++
  }
} else {
  Write-WarnLine "Docker is not available - skipping runtime checks"
  $warned++
}

Write-Host ""
Write-Host "Live Checks" -ForegroundColor Cyan

if (Test-GatewayRunning) {
  $ghResult = Invoke-CmdCapture "docker compose --project-directory `"$root`" exec -T openclaw-gateway sh -lc `"gh api user --jq '.login'`""
  $ghLogin = ($ghResult.Output -join "`n").Trim()
  if ($ghResult.ExitCode -eq 0 -and $ghLogin) {
    Write-Ok "GitHub auth works in gateway as $ghLogin"
  } else {
    Write-WarnLine "GitHub live check failed - verify GITHUB_TOKEN and runtime injection"
    $warned++
  }

  if ($googleRefreshToken) {
    $gcalResult = Invoke-CmdCapture "docker compose --project-directory `"$root`" exec -T openclaw-gateway sh -lc `"gcal list-calendars >/dev/null 2>&1`""
    if ($gcalResult.ExitCode -eq 0) {
      Write-Ok "Google Calendar auth works in gateway"
    } else {
      Write-WarnLine "Google live check failed - re-auth Google and run refresh-google-token"
      $warned++
    }
  } else {
    Write-WarnLine "Skipping Google live check because GOOGLE_REFRESH_TOKEN is not configured"
    $warned++
  }
} else {
  Write-WarnLine "openclaw-gateway is not running - skipping live checks"
  $warned++
}

Write-Host ""
Write-Host "Next Steps" -ForegroundColor Cyan
Write-Host "  - GitHub broken: update GITHUB_TOKEN, then run make inject-tokens or .\scripts\inject-tokens.ps1"
Write-Host "  - Google broken: replace GOOGLE_REFRESH_TOKEN, then run refresh-google-token with restart"
Write-Host "  - LLM OAuth missing: run make login"

Write-Host ""
if ($failed -gt 0) {
  Write-Host "Token health failed: $failed blocking issue(s), $warned warning(s)." -ForegroundColor Red
  exit 1
}

if ($warned -gt 0) {
  Write-Host "Token health completed with $warned warning(s)." -ForegroundColor Yellow
  exit 0
}

Write-Host "Token health passed." -ForegroundColor Green
