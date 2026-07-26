#Requires -Version 5.1
<#
.SYNOPSIS
    Installs a curated list of packages using Windows Package Manager (winget).

.DESCRIPTION
    Ensures winget is available, then installs packages defined in
    winget-packages.yml (or a -PackageList override). Already-installed
    packages are skipped unless -Force is specified (idempotent install path).

.PARAMETER PackageList
    Optional array of package IDs. When supplied, the YAML file is ignored.

.PARAMETER ConfigFile
    Path to the YAML packages file. Defaults to winget-packages.yml next to this script.

.PARAMETER Force
    Forces installation even if packages are already installed.
    With -Thermonuclear, skips the confirmation prompt.

.PARAMETER Quiet
    Suppresses detailed output; only shows errors and final status.

.PARAMETER Thermonuclear
    Uninstalls every package in the list. High-impact; confirms unless -Force.

.EXAMPLE
    .\Install-Packages.ps1

.EXAMPLE
    .\Install-Packages.ps1 -Force

.EXAMPLE
    .\Install-Packages.ps1 -PackageList @('Microsoft.PowerToys', 'Git.Git')

.EXAMPLE
    .\Install-Packages.ps1 -Thermonuclear -Force
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string[]]$PackageList,
    [string]$ConfigFile,
    [switch]$Force,
    [switch]$Quiet,
    [switch]$Thermonuclear
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

Import-Module (Join-Path $PSScriptRoot 'helpers\WingetBootstrap.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'helpers\PackagesYaml.psm1') -Force

function Write-ProgressInfo
{
    param([string]$Message, [switch]$Quiet)
    if (-not $Quiet)
    {
        Write-Host $Message -ForegroundColor Blue
    }
}

function Write-ProgressSuccess
{
    param([string]$Message, [switch]$Quiet)
    if (-not $Quiet)
    {
        Write-Host $Message -ForegroundColor Green
    }
}

function Write-ProgressWarning
{
    param([string]$Message, [switch]$Quiet)
    if (-not $Quiet)
    {
        Write-Warning $Message
    }
}

function Uninstall-WingetPackage
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackageId,
        [switch]$Quiet
    )

    $result = @{
        PackageId = $PackageId
        Success   = $false
        Message   = ''
    }

    try
    {
        Write-ProgressInfo "Processing uninstallation: $PackageId" -Quiet:$Quiet

        $uninstallArgs = @(
            'uninstall',
            '--id', $PackageId,
            '--exact',
            '--silent'
        )

        $null = & winget @uninstallArgs 2>&1

        if ($LASTEXITCODE -eq 0)
        {
            $result.Success = $true
            $result.Message = 'Successfully uninstalled'
            Write-ProgressSuccess "  +- [OK] Successfully uninstalled $PackageId" -Quiet:$Quiet
        }
        else
        {
            $result.Message = "Uninstallation failed (exit code: $LASTEXITCODE)"
            Write-ProgressWarning "  +- [X] Failed to uninstall $PackageId (exit code: $LASTEXITCODE)" -Quiet:$Quiet
        }
    }
    catch
    {
        $result.Message = "Exception during uninstallation: $($_.Exception.Message)"
        Write-ProgressWarning "  +- [X] Exception: $($_.Exception.Message)" -Quiet:$Quiet
    }

    return $result
}

function Install-WingetPackage
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackageId,
        [switch]$Force,
        [switch]$Quiet
    )

    $result = @{
        PackageId        = $PackageId
        Success          = $false
        Message          = ''
        AlreadyInstalled = $false
    }

    try
    {
        Write-ProgressInfo "Processing package: $PackageId" -Quiet:$Quiet

        if (-not $Force)
        {
            $listOutput = & winget list --id $PackageId --exact 2>$null
            if ($LASTEXITCODE -eq 0 -and ($listOutput -match [regex]::Escape($PackageId)))
            {
                $result.AlreadyInstalled = $true
                $result.Success = $true
                $result.Message = 'Already installed'
                Write-ProgressInfo '  +- Package already installed, skipping' -Quiet:$Quiet
                return $result
            }
        }

        Write-ProgressInfo '  +- Installing...' -Quiet:$Quiet

        $installArgs = @(
            'install',
            '--id', $PackageId,
            '--exact',
            '--silent',
            '--accept-package-agreements',
            '--accept-source-agreements'
        )
        if ($Force)
        {
            $installArgs += '--force'
        }

        $output = & winget @installArgs 2>&1

        if ($LASTEXITCODE -eq 0)
        {
            $result.Success = $true
            $result.Message = 'Successfully installed'
            Write-ProgressSuccess "  +- [OK] Successfully installed $PackageId" -Quiet:$Quiet
        }
        elseif ($LASTEXITCODE -eq -1978335189)
        {
            # APPINSTALLER_HRESULT_NO_UPDATE_AVAILABLE / already installed
            $result.Success = $true
            $result.AlreadyInstalled = $true
            $result.Message = 'Already installed (detected during install)'
            Write-ProgressInfo '  +- Package already installed' -Quiet:$Quiet
        }
        else
        {
            $result.Message = "Installation failed (exit code: $LASTEXITCODE)"
            Write-ProgressWarning "  +- [X] Failed to install $PackageId (exit code: $LASTEXITCODE)" -Quiet:$Quiet

            if ($output -match 'No package found matching input criteria')
            {
                $result.Message = 'Package not found in winget repository'
                Write-ProgressWarning '    +- Package not found in repository' -Quiet:$Quiet
            }
            elseif ($output -match 'requires admin privileges')
            {
                $result.Message = 'Requires administrator privileges'
                Write-ProgressWarning '    +- Administrator privileges required' -Quiet:$Quiet
            }
        }
    }
    catch
    {
        $result.Message = "Exception during installation: $($_.Exception.Message)"
        Write-ProgressWarning "  +- [X] Exception: $($_.Exception.Message)" -Quiet:$Quiet
    }

    return $result
}

# ── Main ──────────────────────────────────────────────────────────────────────

Write-Host '=== Package Installation Script ===' -ForegroundColor Cyan
Write-Host ''

if ($PSBoundParameters.ContainsKey('PackageList') -and $PackageList -and $PackageList.Count -gt 0)
{
    Write-ProgressInfo 'Using package list supplied via -PackageList parameter.' -Quiet:$Quiet
}
else
{
    if (-not $PSBoundParameters.ContainsKey('ConfigFile') -or [string]::IsNullOrWhiteSpace($ConfigFile))
    {
        $ConfigFile = Join-Path $PSScriptRoot 'winget-packages.yml'
    }

    Write-ProgressInfo "Loading package list from: $ConfigFile" -Quiet:$Quiet

    try
    {
        $PackageList = Get-PackageIdList -Path $ConfigFile
    }
    catch
    {
        Write-Error $_.Exception.Message
        exit 1
    }

    if (-not $PackageList -or $PackageList.Count -eq 0)
    {
        Write-Error "No packages found in '$ConfigFile'. Aborting."
        exit 1
    }

    Write-ProgressSuccess "[OK] Loaded $($PackageList.Count) packages from YAML" -Quiet:$Quiet
}

Write-Host ''

Write-ProgressInfo 'Step 1: Ensuring winget is available...' -Quiet:$Quiet

if (-not (Assert-WingetAvailable -Quiet:$Quiet))
{
    Write-Error 'Failed to enable winget. Cannot proceed with package installation.'
    Write-Host 'Please ensure you are running as Administrator and try again.' -ForegroundColor Yellow
    exit 1
}

Write-ProgressSuccess '[OK] winget is ready' -Quiet:$Quiet
Write-Host ''

if ($Thermonuclear)
{
    if ($Force)
    {
        Write-ProgressWarning 'Thermonuclear mode: -Force supplied; skipping confirmation.' -Quiet:$Quiet
    }
    else
    {
        $count = $PackageList.Count
        $answer = Read-Host "About to UNINSTALL $count package(s). Type 'yes' to continue"
        if ($answer -ne 'yes')
        {
            Write-Warning 'Thermonuclear uninstall aborted by user. Re-run with -Force to skip confirmation.'
            exit 0
        }
    }

    Write-ProgressInfo '!!! THERMONUCLEAR MODE: Uninstalling all packages !!!' -Quiet:$Quiet
}

Write-ProgressInfo 'Step 2: Processing packages...' -Quiet:$Quiet
Write-ProgressInfo "Packages to process: $($PackageList.Count)" -Quiet:$Quiet
Write-Host ''

$results = @()
$successCount = 0
$alreadyInstalledCount = 0
$failedCount = 0

foreach ($package in $PackageList)
{
    if ($Thermonuclear)
    {
        $result = Uninstall-WingetPackage -PackageId $package -Quiet:$Quiet
    }
    else
    {
        $result = Install-WingetPackage -PackageId $package -Force:$Force -Quiet:$Quiet
    }
    $results += $result

    if ($result.Success)
    {
        if ($Thermonuclear)
        {
            $successCount++
        }
        elseif ($result.AlreadyInstalled)
        {
            $alreadyInstalledCount++
        }
        else
        {
            $successCount++
        }
    }
    else
    {
        $failedCount++
    }
}

Write-Host ''
$modeLabel = if ($Thermonuclear) { 'Uninstallation' } else { 'Installation' }
Write-Host "=== $modeLabel Summary ===" -ForegroundColor Cyan
Write-Host "Total packages processed : $($PackageList.Count)" -ForegroundColor White
$successLabel = if ($Thermonuclear) { 'uninstalled' } else { 'installed' }
Write-Host "Successfully $successLabel   : $successCount" -ForegroundColor Green
if (-not $Thermonuclear)
{
    Write-Host "Already installed        : $alreadyInstalledCount" -ForegroundColor Blue
}
Write-Host "Failed operations        : $failedCount" -ForegroundColor Red

if ($failedCount -gt 0)
{
    Write-Host ''
    Write-Host 'Failed packages:' -ForegroundColor Red
    foreach ($result in ($results | Where-Object { -not $_.Success }))
    {
        Write-Host "  * $($result.PackageId): $($result.Message)" -ForegroundColor Red
    }
}

if (-not $Quiet -and $results.Count -gt 0)
{
    Write-Host ''
    Write-Host 'Detailed results:' -ForegroundColor Gray
    foreach ($result in $results)
    {
        if ($result.Success)
        {
            if ($result.AlreadyInstalled)
            {
                $status = 'Already Installed'
                $color = 'Blue'
            }
            else
            {
                $status = if ($Thermonuclear) { 'Uninstalled' } else { 'Installed' }
                $color = 'Green'
            }
        }
        else
        {
            $status = 'Failed'
            $color = 'Red'
        }

        Write-Host "  $($result.PackageId): $status" -ForegroundColor $color
    }
}

Write-Host ''

if ($failedCount -eq 0)
{
    Write-Host '[OK] All packages processed successfully!' -ForegroundColor Green
    exit 0
}

Write-Host '[WARN] Some packages failed. Check the summary above for details.' -ForegroundColor Yellow
exit 1
