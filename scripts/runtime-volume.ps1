#!/usr/bin/env pwsh

function Get-ComposeProjectName {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Root
  )

  if ($env:COMPOSE_PROJECT_NAME) {
    return $env:COMPOSE_PROJECT_NAME
  }

  return ((Split-Path -Leaf $Root).ToLowerInvariant() -replace "[^a-z0-9]+", "-").TrimEnd("-")
}

function Get-RuntimeVolumeName {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Root
  )

  return "$(Get-ComposeProjectName -Root $Root)_openclaw_run"
}
