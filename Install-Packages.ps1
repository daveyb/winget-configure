<#
.SYNOPSIS
    Installs a curated list of packages using Windows Package Manager (winget).

.DESCRIPTION
    This script ensures winget is available and functional, then installs a predefined
    list of packages. It includes error handling and progress reporting for each package.

.PARAMETER PackageList
    Optional array of package IDs to install. If not specified, uses the default list.

.PARAMETER Force
    Forces installation even if packages are already installed

.PARAMETER Quiet
    Suppresses detailed output, only shows errors and final status

.EXAMPLE
    .\Install-Packages.ps1
    Installs the default package list

.EXAMPLE
    .\Install-Packages.ps1 -Force
    Forces installation of all packages

.EXAMPLE
    .\Install-Packages.ps1 -PackageList @("Microsoft.PowerToys", "Git.Git")
    Installs only the specified packages

.NOTES
    Requires administrator privileges
    Compatible with Windows 10 1809+ and Windows 11
#>

[CmdletBinding()]
param(
    [string[]]$PackageList = @(
        "Amazon.AWSCLI",
        "Automattic.PocketCasts",
        "Canonical.Ubuntu.2404",
        "calibre.calibre",
        "eloston.ungoogled-chromium",
        "Git.Git",
        "GitHub.cli",
        "GoLang.Go",
        "Hashicorp.Terraform",
        "JanDeDobbeleer.OhMyPosh",
        "LinuxContainers.Incus",
        "Microsoft.AzureCLI",
        "Microsoft.PowerToys",
        "Microsoft.Sysinternals.Suite",
        "Proton.ProtonDrive",
        "Proton.ProtonVPN",
        "Python.Python.3.14",
        "RubyInstallerTeam.RubyWithDevKit.3.4",
        "Spotify.Spotify",
        "SUSE.RancherDesktop",
        "Tailscale.Tailscale",
        "ZedIndustries.Zed",
        "Zoom.Zoom"
    ),
    [switch]$Force,
    [switch]$Quiet
)

# Import the winget helper module
$helperPath = Join-Path $PSScriptRoot "helpers\Ensure-Winget.psm1"

if (-not (Test-Path $helperPath)) {
    Write-Error "Helper module not found at: $helperPath"
    Write-Error "Please ensure the helpers directory and Ensure-Winget.psm1 exist"
    exit 1
}

# Import the helper module
Import-Module $helperPath -Force

function Write-ProgressInfo {
    param(
        [string]$Message,
        [switch]$Quiet
    )
    if (-not $Quiet) {
        Write-Host $Message -ForegroundColor Blue
    }
}

function Write-ProgressSuccess {
    param(
        [string]$Message,
        [switch]$Quiet
    )
    if (-not $Quiet) {
        Write-Host $Message -ForegroundColor Green
    }
}

function Write-ProgressWarning {
    param(
        [string]$Message,
        [switch]$Quiet
    )
    if (-not $Quiet) {
        Write-Warning $Message
    }
}

function Install-WingetPackage {
    <#
    .SYNOPSIS
    Installs a single package using winget

    .PARAMETER PackageId
    The winget package ID to install

    .PARAMETER Force
    Forces installation even if already installed

    .OUTPUTS
    Returns hashtable with success status and details
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackageId,
        [switch]$Force,
        [switch]$Quiet
    )

    $result = @{
        PackageId = $PackageId
        Success = $false
        Message = ""
        AlreadyInstalled = $false
    }

    try {
        Write-ProgressInfo "Processing package: $PackageId" -Quiet:$Quiet

        # Check if already installed (unless Force is specified)
        if (-not $Force) {
            $listOutput = winget list --id $PackageId --exact 2>$null
            if ($LASTEXITCODE -eq 0 -and $listOutput -match $PackageId) {
                $result.AlreadyInstalled = $true
                $result.Success = $true
                $result.Message = "Already installed"
                Write-ProgressInfo "  └─ Package already installed, skipping" -Quiet:$Quiet
                return $result
            }
        }

        # Install the package
        Write-ProgressInfo "  └─ Installing..." -Quiet:$Quiet

        $installArgs = @("install", "--id", $PackageId, "--exact", "--silent", "--accept-package-agreements", "--accept-source-agreements")

        if ($Force) {
            $installArgs += "--force"
        }

        $output = & winget $installArgs 2>&1

        if ($LASTEXITCODE -eq 0) {
            $result.Success = $true
            $result.Message = "Successfully installed"
            Write-ProgressSuccess "  └─ ✓ Successfully installed $PackageId" -Quiet:$Quiet
        }
        elseif ($LASTEXITCODE -eq -1978335189) {
            # Package already installed
            $result.Success = $true
            $result.AlreadyInstalled = $true
            $result.Message = "Already installed (detected during install)"
            Write-ProgressInfo "  └─ Package already installed" -Quiet:$Quiet
        }
        else {
            $result.Message = "Installation failed (Exit code: $LASTEXITCODE)"
            Write-ProgressWarning "  └─ ✗ Failed to install $PackageId (Exit code: $LASTEXITCODE)" -Quiet:$Quiet

            # Try to extract more specific error information
            if ($output -match "No package found matching input criteria") {
                $result.Message = "Package not found in winget repository"
                Write-ProgressWarning "    └─ Package not found in repository" -Quiet:$Quiet
            }
            elseif ($output -match "requires admin privileges") {
                $result.Message = "Requires administrator privileges"
                Write-ProgressWarning "    └─ Administrator privileges required" -Quiet:$Quiet
            }
        }
    }
    catch {
        $result.Message = "Exception during installation: $($_.Exception.Message)"
        Write-ProgressWarning "  └─ ✗ Exception: $($_.Exception.Message)" -Quiet:$Quiet
    }

    return $result
}

# Main script execution
Write-Host "=== Package Installation Script ===" -ForegroundColor Cyan
Write-Host ""

# Step 1: Ensure winget is available
Write-ProgressInfo "Step 1: Ensuring winget is available..." -Quiet:$Quiet

if (-not (Ensure-Winget -Quiet:$Quiet)) {
    Write-Error "Failed to enable winget. Cannot proceed with package installation."
    Write-Host "Please ensure you are running as Administrator and try again." -ForegroundColor Yellow
    exit 1
}

Write-ProgressSuccess "✓ winget is ready" -Quiet:$Quiet
Write-Host ""

# Step 2: Install packages
Write-ProgressInfo "Step 2: Installing packages..." -Quiet:$Quiet
Write-ProgressInfo "Packages to install: $($PackageList.Count)" -Quiet:$Quiet

$results = @()
$successCount = 0
$alreadyInstalledCount = 0
$failedCount = 0

foreach ($package in $PackageList) {
    $result = Install-WingetPackage -PackageId $package -Force:$Force -Quiet:$Quiet
    $results += $result

    if ($result.Success) {
        if ($result.AlreadyInstalled) {
            $alreadyInstalledCount++
        } else {
            $successCount++
        }
    } else {
        $failedCount++
    }
}

# Step 3: Summary
Write-Host ""
Write-Host "=== Installation Summary ===" -ForegroundColor Cyan

Write-Host "Total packages processed: $($PackageList.Count)" -ForegroundColor White
Write-Host "Successfully installed: $successCount" -ForegroundColor Green
Write-Host "Already installed: $alreadyInstalledCount" -ForegroundColor Blue
Write-Host "Failed installations: $failedCount" -ForegroundColor Red

if ($failedCount -gt 0) {
    Write-Host ""
    Write-Host "Failed packages:" -ForegroundColor Red
    foreach ($result in $results | Where-Object { -not $_.Success }) {
        Write-Host "  • $($result.PackageId): $($result.Message)" -ForegroundColor Red
    }
}

if (-not $Quiet -and $results.Count -gt 0) {
    Write-Host ""
    Write-Host "Detailed results:" -ForegroundColor Gray
    foreach ($result in $results) {
        $status = if ($result.Success) {
            if ($result.AlreadyInstalled) { "Already Installed" } else { "Installed" }
        } else {
            "Failed"
        }
        $color = if ($result.Success) {
            if ($result.AlreadyInstalled) { "Blue" } else { "Green" }
        } else {
            "Red"
        }
        Write-Host "  $($result.PackageId): $status" -ForegroundColor $color
    }
}

Write-Host ""

# Exit with appropriate code
if ($failedCount -eq 0) {
    Write-Host "✓ All packages processed successfully!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "⚠ Some packages failed to install. Check the summary above for details." -ForegroundColor Yellow
    exit 1
}
