#Requires -Version 5.1
<#
.SYNOPSIS
    Installs a curated list of packages using Windows Package Manager (winget).

.DESCRIPTION
    This script ensures winget is available and functional, then installs packages
    defined in winget-packages.yml (located alongside this script).  The YAML file
    is parsed without any external module dependency.

    A -PackageList override can be supplied on the command line to bypass the YAML
    file entirely, preserving backwards-compatible behaviour.

.PARAMETER PackageList
    Optional array of package IDs to install.  If not specified the package list is
    loaded from winget-packages.yml in the same directory as this script.

.PARAMETER ConfigFile
    Path to the YAML packages file.  Defaults to winget-packages.yml next to this
    script.

.PARAMETER Force
    Forces installation even if packages are already installed.

.PARAMETER Quiet
    Suppresses detailed output, only shows errors and final status.

.EXAMPLE
    .\Install-Packages.ps1
    Installs all packages defined in winget-packages.yml

.EXAMPLE
    .\Install-Packages.ps1 -Force
    Forces (re)installation of all packages defined in winget-packages.yml

.EXAMPLE
    .\Install-Packages.ps1 -PackageList @("Microsoft.PowerToys", "Git.Git")
    Installs only the specified packages (ignores winget-packages.yml)

.EXAMPLE
    .\Install-Packages.ps1 -ConfigFile "C:\custom\my-packages.yml"
    Installs packages from the specified YAML file

.NOTES
    Requires administrator privileges.
    Compatible with Windows 10 1809+ and Windows 11.
#>

[CmdletBinding()]
param(
    [string[]]$PackageList,

    [string]$ConfigFile,

    [switch]$Force,

    [switch]$Quiet,

    [switch]$Thermonuclear
)

# ── Helpers ───────────────────────────────────────────────────────────────────

function Uninstall-WingetPackage
{
    <#
    .SYNOPSIS
        Uninstalls a single package using winget.

    .PARAMETER PackageId
        The winget package ID to uninstall.

    .OUTPUTS
        Hashtable with keys: PackageId, Success, Message.
    #>
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
            '--id',    $PackageId,
            '--exact',
            '--silent'
        )

        $output = & winget $uninstallArgs 2>&1

        if ($LASTEXITCODE -eq 0)
        {
            $result.Success = $true
            $result.Message = 'Successfully uninstalled'
            Write-ProgressSuccess "  └─ ✓ Successfully uninstalled $PackageId" -Quiet:$Quiet
        } else
        {
            $result.Message = "Uninstallation failed (exit code: $LASTEXITCODE)"
            Write-ProgressWarning "  └─ ✗ Failed to uninstall $PackageId (exit code: $LASTEXITCODE)" -Quiet:$Quiet
        }
    } catch
    {
        $result.Message = "Exception during uninstallation: $($_.Exception.Message)"
        Write-ProgressWarning "  └─ ✗ Exception: $($_.Exception.Message)" -Quiet:$Quiet
    }

    return $result
}

function Write-ProgressInfo
{
    param([string]$Message, [switch]$Quiet)
    if (-not $Quiet)
    { Write-Host $Message -ForegroundColor Blue 
    }
}

function Write-ProgressSuccess
{
    param([string]$Message, [switch]$Quiet)
    if (-not $Quiet)
    { Write-Host $Message -ForegroundColor Green 
    }
}

function Write-ProgressWarning
{
    param([string]$Message, [switch]$Quiet)
    if (-not $Quiet)
    { Write-Warning $Message 
    }
}

# ── Lightweight YAML parser ───────────────────────────────────────────────────
#
# Handles the specific subset of YAML used in winget-packages.yml:
#
#   packages:
#     category_name:       ← ignored (category header)
#       - PackageId        ← collected
#       - PackageId  # optional inline comment  ← collected, comment stripped
#
# Rules:
#   • Lines whose first non-whitespace character is '#' are comments → skip.
#   • Blank lines → skip.
#   • Lines that match /^\s+-\s+(\S+)/ are list items → capture group 1.
#   • Everything else (top-level keys, category keys) → skip.

function Read-WingetPackagesYaml
{
    <#
    .SYNOPSIS
        Parses a winget-packages.yml file and returns a flat array of package IDs.

    .PARAMETER Path
        Full path to the YAML file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path))
    {
        Write-Error "Packages config file not found: $Path"
        return @()
    }

    $packages = [System.Collections.Generic.List[string]]::new()

    foreach ($line in Get-Content -Path $Path -Encoding UTF8)
    {
        # Skip blank lines
        if ([string]::IsNullOrWhiteSpace($line))
        { continue 
        }

        # Skip comment-only lines
        if ($line -match '^\s*#')
        { continue 
        }

        # Capture list items:  <whitespace> - <PackageId> [# optional comment]
        if ($line -match '^\s+-\s+(\S+)')
        {
            $packageId = $Matches[1].Trim()

            # Strip any trailing inline comment that somehow ended up attached
            # (e.g. if the ID were written without a space before #)
            $packageId = $packageId -replace '#.*$', ''
            $packageId = $packageId.Trim()

            if ($packageId -ne '')
            {
                $packages.Add($packageId)
            }
        }
        # All other lines (keys, separators, etc.) are intentionally ignored.
    }

    return $packages.ToArray()
}

# ── Package installer ─────────────────────────────────────────────────────────

function Install-WingetPackage
{
    <#
    .SYNOPSIS
        Installs a single package using winget.

    .PARAMETER PackageId
        The winget package ID to install.

    .PARAMETER Force
        Forces installation even if already installed.

    .OUTPUTS
        Hashtable with keys: PackageId, Success, Message, AlreadyInstalled.
    #>
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

        # Check if already installed (skip when -Force is set)
        if (-not $Force)
        {
            $listOutput = winget list --id $PackageId --exact 2>$null
            if ($LASTEXITCODE -eq 0 -and $listOutput -match [regex]::Escape($PackageId))
            {
                $result.AlreadyInstalled = $true
                $result.Success          = $true
                $result.Message          = 'Already installed'
                Write-ProgressInfo "  └─ Package already installed, skipping" -Quiet:$Quiet
                return $result
            }
        }

        Write-ProgressInfo "  └─ Installing..." -Quiet:$Quiet

        $installArgs = @(
            'install',
            '--id',    $PackageId,
            '--exact',
            '--silent',
            '--accept-package-agreements',
            '--accept-source-agreements'
        )
        if ($Force)
        { $installArgs += '--force' 
        }

        $output = & winget $installArgs 2>&1

        if ($LASTEXITCODE -eq 0)
        {
            $result.Success = $true
            $result.Message = 'Successfully installed'
            Write-ProgressSuccess "  └─ ✓ Successfully installed $PackageId" -Quiet:$Quiet
        } elseif ($LASTEXITCODE -eq -1978335189)
        {
            # APPINSTALLER_HRESULT_NO_UPDATE_AVAILABLE / already installed
            $result.Success          = $true
            $result.AlreadyInstalled = $true
            $result.Message          = 'Already installed (detected during install)'
            Write-ProgressInfo "  └─ Package already installed" -Quiet:$Quiet
        } else
        {
            $result.Message = "Installation failed (exit code: $LASTEXITCODE)"
            Write-ProgressWarning "  └─ ✗ Failed to install $PackageId (exit code: $LASTEXITCODE)" -Quiet:$Quiet

            if ($output -match 'No package found matching input criteria')
            {
                $result.Message = 'Package not found in winget repository'
                Write-ProgressWarning "    └─ Package not found in repository" -Quiet:$Quiet
            } elseif (($output -match '0x80073d28') -or ($output -match 'administrator privileges are required') -or ($output -match 'requires admin privileges'))
            {
                $result.Message = 'Requires administrator privileges'
                Write-ProgressWarning "    └─ Administrator privileges required" -Quiet:$Quiet
            }
        }
    } catch
    {
        $result.Message = "Exception during installation: $($_.Exception.Message)"
        Write-ProgressWarning "  └─ ✗ Exception: $($_.Exception.Message)" -Quiet:$Quiet
    }

    return $result
}

# ── Main ──────────────────────────────────────────────────────────────────────

Write-Host '=== Package Installation Script ===' -ForegroundColor Cyan
Write-Host ''

# Step 0: Resolve the winget helper module
$helperPath = Join-Path $PSScriptRoot 'helpers\Ensure-Winget.psm1'
$wslHelperPath = Join-Path $PSScriptRoot 'helpers\Update-Wsl.psm1'

if (-not (Test-Path $helperPath))
{
    Write-Error "Helper module not found at: $helperPath"
    Write-Error 'Please ensure the helpers directory and Ensure-Winget.psm1 exist.'
    exit 1
}

Import-Module $helperPath -Force
if (Test-Path -LiteralPath $wslHelperPath)
{
    Import-Module $wslHelperPath -Force
}

# Step 1: Build the package list ──────────────────────────────────────────────
#
# Priority:
#   1. -PackageList parameter (explicit override – skip YAML entirely)
#   2. -ConfigFile parameter  (explicit YAML path)
#   3. winget-packages.yml next to this script (default)

if ($PSBoundParameters.ContainsKey('PackageList') -and $PackageList.Count -gt 0)
{
    Write-ProgressInfo 'Using package list supplied via -PackageList parameter.' -Quiet:$Quiet
} else
{
    # Resolve config file path
    if (-not $PSBoundParameters.ContainsKey('ConfigFile') -or [string]::IsNullOrWhiteSpace($ConfigFile))
    {
        $ConfigFile = Join-Path $PSScriptRoot 'winget-packages.yml'
    }

    Write-ProgressInfo "Loading package list from: $ConfigFile" -Quiet:$Quiet

    $PackageList = Read-WingetPackagesYaml -Path $ConfigFile

    if ($PackageList.Count -eq 0)
    {
        Write-Error "No packages found in '$ConfigFile'. Aborting."
        exit 1
    }

    Write-ProgressSuccess "✓ Loaded $($PackageList.Count) packages from YAML" -Quiet:$Quiet
}

Write-Host ''

# Step 2: Ensure winget is available ──────────────────────────────────────────
Write-ProgressInfo 'Step 1: Ensuring winget is available...' -Quiet:$Quiet

if (-not (Ensure-Winget -Quiet:$Quiet))
{
    Write-Error 'Failed to enable winget. Cannot proceed with package installation.'
    Write-Host 'Please ensure you are running as Administrator and try again.' -ForegroundColor Yellow
    exit 1
}

Write-ProgressSuccess '✓ winget is ready' -Quiet:$Quiet
Write-Host ''

# Step 3: Process packages ────────────────────────────────────────────────────
Write-ProgressInfo 'Step 2: Processing packages...' -Quiet:$Quiet
if ($Thermonuclear)
{
    Write-ProgressInfo '!!! THERMONUCLEAR MODE ENABLED: Uninstalling all packages !!!' -Quiet:$Quiet
}
Write-ProgressInfo "Packages to process: $($PackageList.Count)" -Quiet:$Quiet
Write-Host ''

$results              = @()
$successCount         = 0
$alreadyInstalledCount = 0
$failedCount          = 0

foreach ($package in $PackageList)
{
    if ($Thermonuclear)
    {
        $result = Uninstall-WingetPackage -PackageId $package -Quiet:$Quiet
    } else
    {
        if (($package -eq 'Microsoft.WSL') -and (Get-Command -Name Update-Wsl -ErrorAction SilentlyContinue))
        {
            # Skip winget: a blocking Microsoft.WSL pin makes install/upgrade
            # fail with a pin error (not 0x80073d28), so the old fallback
            # never ran. Match winget configure: always use Update-Wsl.
            Write-ProgressInfo "Processing package: $package" -Quiet:$Quiet
            Write-ProgressInfo "  └─ Skipping winget; using wsl --update --web-download" -Quiet:$Quiet
            $wslResult = Update-Wsl -Quiet:$Quiet
            $result = @{
                PackageId        = $package
                Success          = [bool]$wslResult.Success
                Message          = [string]$wslResult.Message
                AlreadyInstalled = $false
            }
            if ($result.Success)
            {
                Write-ProgressSuccess "  └─ ✓ WSL via web-download" -Quiet:$Quiet
            }
            else
            {
                Write-ProgressWarning "  └─ ✗ WSL web-download failed" -Quiet:$Quiet
            }
        }
        else
        {
            $result = Install-WingetPackage -PackageId $package -Force:$Force -Quiet:$Quiet
        }
    }
    $results += $result

    if ($result.Success)
    {
        if ($Thermonuclear)
        {
            $successCount++
        } else
        {
            if ($result.AlreadyInstalled)
            { $alreadyInstalledCount++ 
            } else
            { $successCount++ 
            }
        }
    } else
    {
        $failedCount++
    }
}

# Step 4: Summary ──────────────────────────────────────────────────────────────
Write-Host ''
Write-Host "=== $(if ($Thermonuclear) { 'Uninstallation' } else { 'Installation' }) Summary ===" -ForegroundColor Cyan
Write-Host "Total packages processed : $($PackageList.Count)" -ForegroundColor White
Write-Host "Successfully $(if ($Thermonuclear) { 'uninstalled' } else { 'installed' })   : $successCount" -ForegroundColor Green
if (-not $Thermonuclear)
{
    Write-Host "Already installed        : $alreadyInstalledCount" -ForegroundColor Blue
}
Write-Host "Failed operations        : $failedCount"            -ForegroundColor Red

if ($failedCount -gt 0)
{
    Write-Host ''
    Write-Host 'Failed packages:' -ForegroundColor Red
    foreach ($result in ($results | Where-Object { -not $_.Success }))
    {
        Write-Host "  • $($result.PackageId): $($result.Message)" -ForegroundColor Red
    }
}

if (-not $Quiet -and $results.Count -gt 0)
{
    Write-Host ''
    Write-Host 'Detailed results:' -ForegroundColor Gray
    foreach ($result in $results)
    {
        $status = if ($result.Success)
        {
            if ($result.AlreadyInstalled)
            { 'Already Installed' 
            } else
            { 'Installed' 
            }
        } else
        { 'Failed' 
        }

        $color = if ($result.Success)
        {
            if ($result.AlreadyInstalled)
            { 'Blue' 
            } else
            { 'Green' 
            }
        } else
        { 'Red' 
        }

        Write-Host "  $($result.PackageId): $status" -ForegroundColor $color
    }
}

Write-Host ''

if ($failedCount -eq 0)
{
    Write-Host '✓ All packages processed successfully!' -ForegroundColor Green
    exit 0
} else
{
    Write-Host '⚠ Some packages failed to install. Check the summary above for details.' -ForegroundColor Yellow
    exit 1
}
