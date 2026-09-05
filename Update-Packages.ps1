#Requires -Version 5.1
<#
.SYNOPSIS
    Upgrade winget packages, then update WSL via web-download.

.DESCRIPTION
    `winget upgrade --all` tries to update Microsoft.WSL through the MSIX installer
    and fails with 0x80073d28 when administrator privileges are required.

    This script:
      1. Pins Microsoft.WSL so `winget upgrade --all` skips it
      2. Runs `winget upgrade --all` for every other package
      3. Updates WSL with `wsl --update --web-download`

.PARAMETER SkipWingetUpgrade
    Only pin and update WSL; do not run `winget upgrade --all`.

.PARAMETER SkipWsl
    Only run `winget upgrade --all` (still pins Microsoft.WSL first).

.PARAMETER Quiet
    Suppress informational output.

.EXAMPLE
    .\Update-Packages.ps1
    Upgrade all winget packages and WSL.

.EXAMPLE
    .\Update-Packages.ps1 -SkipWingetUpgrade
    Only update WSL via web-download.
#>

[CmdletBinding()]
param(
    [switch]$SkipWingetUpgrade,
    [switch]$SkipWsl,
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$wslHelper = Join-Path $ScriptDir 'helpers\Update-Wsl.psm1'
$wingetHelper = Join-Path $ScriptDir 'helpers\Ensure-Winget.psm1'

function Write-Step
{
    param([string]$Message)
    if (-not $Quiet)
    {
        Write-Host $Message -ForegroundColor Blue
    }
}

function Write-Ok
{
    param([string]$Message)
    if (-not $Quiet)
    {
        Write-Host $Message -ForegroundColor Green
    }
}

if (-not (Test-Path -LiteralPath $wslHelper))
{
    Write-Error "Helper module not found: $wslHelper"
    exit 1
}

Import-Module $wslHelper -Force

if (Test-Path -LiteralPath $wingetHelper)
{
    Import-Module $wingetHelper -Force
    if (Get-Command -Name Ensure-Winget -ErrorAction SilentlyContinue)
    {
        $null = Ensure-Winget -Quiet:$Quiet
    }
}

Write-Host '=== Package Update ===' -ForegroundColor Cyan
Write-Host ''

Write-Step 'Step 1: Pin Microsoft.WSL so winget upgrade skips the MSIX installer'
$pinned = Add-WslWingetPin -Quiet:$Quiet
if (-not $pinned)
{
    Write-Warning 'WSL pin was not applied. winget upgrade --all may still fail with 0x80073d28.'
}

$upgradeFailed = $false
if (-not $SkipWingetUpgrade)
{
    Write-Host ''
    Write-Step 'Step 2: winget upgrade --all'
    $upgradeArgs = @(
        'upgrade',
        '--all',
        '--accept-package-agreements',
        '--accept-source-agreements',
        '--disable-interactivity'
    )
    & winget @upgradeArgs
    if ($LASTEXITCODE -ne 0)
    {
        $upgradeFailed = $true
        Write-Warning "winget upgrade --all exited $LASTEXITCODE"
    }
    else
    {
        Write-Ok '[OK] winget upgrade --all finished'
    }
}

$wslFailed = $false
if (-not $SkipWsl)
{
    Write-Host ''
    Write-Step 'Step 3: Update WSL via wsl --update --web-download'
    $wslResult = Update-Wsl -Quiet:$Quiet
    if (-not $wslResult.Success)
    {
        $wslFailed = $true
    }
}

Write-Host ''
if ($upgradeFailed -or $wslFailed)
{
    Write-Warning 'One or more update steps failed. See output above.'
    exit 1
}

Write-Ok '[OK] Updates complete'
exit 0
