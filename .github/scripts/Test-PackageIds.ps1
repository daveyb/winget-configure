#Requires -Version 5.1
<#
.SYNOPSIS
    Validates that every package ID in winget-packages.yml exists in the winget source.
#>

[CmdletBinding()]
param(
    [string]$PackagesFile = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'winget-packages.yml')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if (-not (Test-Path -LiteralPath $PackagesFile))
{
    $PackagesFile = Join-Path $repoRoot 'winget-packages.yml'
}

Import-Module (Join-Path $repoRoot 'helpers\PackagesYaml.psm1') -Force

if (-not (Get-Command winget -ErrorAction SilentlyContinue))
{
    throw 'winget is not available on PATH.'
}

$entries = @(Read-PackagesYaml -Path $PackagesFile)
if ($entries.Count -eq 0)
{
    throw "No packages found in $PackagesFile"
}

$failed = New-Object System.Collections.Generic.List[string]
$ok = 0

Write-Host "Validating $($entries.Count) package ID(s) against winget..." -ForegroundColor Cyan

foreach ($entry in $entries)
{
    $id = [string]$entry.Id
    $null = & winget show --id $id --exact --accept-source-agreements 2>&1
    if ($LASTEXITCODE -eq 0)
    {
        $ok++
        Write-Host "  [OK] $id" -ForegroundColor Green
    }
    else
    {
        $failed.Add($id) | Out-Null
        Write-Host "  [X]  $id" -ForegroundColor Red
    }
}

Write-Host ''
Write-Host "Valid: $ok  Missing: $($failed.Count)" -ForegroundColor White

if ($failed.Count -gt 0)
{
    Write-Host 'Unknown package IDs:' -ForegroundColor Red
    foreach ($id in $failed)
    {
        Write-Host "  - $id" -ForegroundColor Red
    }
    exit 1
}

Write-Host '[OK] All package IDs resolved.' -ForegroundColor Green
exit 0
