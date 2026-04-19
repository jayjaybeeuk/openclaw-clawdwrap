#!/usr/bin/env pwsh
# scripts/refresh-google-token.ps1 — Refresh GOOGLE_ACCESS_TOKEN using
# GOOGLE_REFRESH_TOKEN from .env and optionally sync runtime secrets.
#
# Native PowerShell equivalent of scripts/refresh-google-token.sh for Windows
# users running docker compose directly without WSL/Git Bash.

[CmdletBinding()]
param(
  [string]$EnvFile = ".env",
  [switch]$SyncRuntime,
  [switch]$Restart
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot "runtime-volume.ps1")
. (Join-Path $PSScriptRoot "env-utils.ps1")

if (-not [System.IO.Path]::IsPathRooted($EnvFile)) {
  $EnvFile = Join-Path $root $EnvFile
}

function Write-EnvValue {
  param(
    [string]$Key,
    [string]$Value,
    [string]$Path
  )

  $lines = if (Test-Path -LiteralPath $Path) {
    Get-Content -LiteralPath $Path
  } else {
    @()
  }

  $updated = $false
  $result = foreach ($line in $lines) {
    if ($line -match "^${Key}=") {
      $updated = $true
      "${Key}=${Value}"
    } else {
      $line
    }
  }

  if (-not $updated) {
    $result += "${Key}=${Value}"
  }

  $content = ($result -join "`n") + "`n"
  [System.IO.File]::WriteAllText($Path, $content, [System.Text.UTF8Encoding]::new($false))
}

if (-not (Test-Path -LiteralPath $EnvFile)) {
  throw "Env file not found: $EnvFile"
}

$envLines = Get-Content -LiteralPath $EnvFile
$clientId = Read-EnvValue -Key "GOOGLE_CLIENT_ID" -Lines $envLines
$clientSecret = Read-EnvValue -Key "GOOGLE_CLIENT_SECRET" -Lines $envLines
$refreshToken = Read-EnvValue -Key "GOOGLE_REFRESH_TOKEN" -Lines $envLines
$githubToken = Read-EnvValue -Key "GITHUB_TOKEN" -Lines $envLines
$anthropicKey = Read-EnvValue -Key "ANTHROPIC_API_KEY" -Lines $envLines
$azureToken = Read-EnvValue -Key "AZURE_DEVOPS_TOKEN" -Lines $envLines

if ([string]::IsNullOrWhiteSpace($clientId) -or [string]::IsNullOrWhiteSpace($clientSecret) -or [string]::IsNullOrWhiteSpace($refreshToken)) {
  throw "Missing GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET / GOOGLE_REFRESH_TOKEN in $EnvFile"
}

try {
  $response = Invoke-RestMethod `
    -Method Post `
    -Uri "https://oauth2.googleapis.com/token" `
    -ContentType "application/x-www-form-urlencoded" `
    -Body @{
      client_id = $clientId
      client_secret = $clientSecret
      refresh_token = $refreshToken
      grant_type = "refresh_token"
    }
} catch {
  $webResponse = $_.Exception.Response
  if ($webResponse -and $webResponse.GetResponseStream) {
    $reader = New-Object System.IO.StreamReader($webResponse.GetResponseStream())
    $body = $reader.ReadToEnd()
    $reader.Dispose()
    throw "Google token refresh failed: $body"
  }
  throw
}

if (-not $response.access_token) {
  throw "Failed to refresh access token."
}

$accessToken = [string]$response.access_token
$expiresIn = if ($null -ne $response.expires_in) { [string]$response.expires_in } else { "" }

Write-EnvValue -Key "GOOGLE_ACCESS_TOKEN" -Value $accessToken -Path $EnvFile
if ($expiresIn) {
  Write-EnvValue -Key "GOOGLE_ACCESS_TOKEN_EXPIRES_IN" -Value $expiresIn -Path $EnvFile
}

Write-Host "Updated GOOGLE_ACCESS_TOKEN in $EnvFile"

if ($SyncRuntime -or $Restart) {
  $volume = Get-RuntimeVolumeName -Root $root
  $runtimeLines = New-Object System.Collections.Generic.List[string]

  if ($githubToken) { [void]$runtimeLines.Add("GITHUB_TOKEN=$githubToken") }
  if ($anthropicKey) { [void]$runtimeLines.Add("ANTHROPIC_API_KEY=$anthropicKey") }
  if ($azureToken) { [void]$runtimeLines.Add("AZURE_DEVOPS_TOKEN=$azureToken") }
  if ($clientId) { [void]$runtimeLines.Add("GOOGLE_CLIENT_ID=$clientId") }
  if ($clientSecret) { [void]$runtimeLines.Add("GOOGLE_CLIENT_SECRET=$clientSecret") }
  if ($refreshToken) { [void]$runtimeLines.Add("GOOGLE_REFRESH_TOKEN=$refreshToken") }
  [void]$runtimeLines.Add("GOOGLE_ACCESS_TOKEN=$accessToken")

  $runtimeContent = ($runtimeLines -join "`n") + "`n"

  Write-Host "Syncing runtime secrets to volume $volume"
  $runtimeContent |
    docker run --rm -i `
      -v "${volume}:/run/openclaw" `
      alpine sh -lc "umask 077; tr -d '\r' > /run/openclaw/env; chown 1000:1000 /run/openclaw/env; chmod 600 /run/openclaw/env"

  Write-Host "Synced /run/openclaw/env in volume $volume"
}

if ($Restart) {
  docker compose --project-directory $root restart clawwrapd openclaw-gateway | Out-Null
  Write-Host "Restarted clawwrapd and openclaw-gateway"
}
