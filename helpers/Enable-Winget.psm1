<#
.SYNOPSIS
    Checks if Windows Package Manager (winget) is enabled and enables it if necessary.

.DESCRIPTION
    This script performs the following actions:
    1. Checks if winget is available and functional
    2. Verifies if the App Installer package is installed
    3. Enables winget if it's not already enabled
    4. Installs or updates the App Installer package if needed

.PARAMETER Force
    Forces reinstallation of winget even if it appears to be working

.EXAMPLE
    .\Enable-Winget.ps1
    Checks and enables winget if necessary

.EXAMPLE
    .\Enable-Winget.ps1 -Force
    Forces reinstallation of winget

.NOTES
    Requires PowerShell 5.1 or later
    Requires administrator privileges for installation
    Compatible with Windows 10 1809+ and Windows 11
#>

[CmdletBinding()]
param(
    [switch]$Force
)

# Ensure we're running with appropriate privileges
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "This script requires administrator privileges to install winget if it's not present."
    Write-Host "Please run PowerShell as Administrator and try again." -ForegroundColor Yellow
    exit 1
}

function Test-WingetAvailable {
    <#
    .SYNOPSIS
    Tests if winget is available and functional
    #>
    try {
        $null = Get-Command winget -ErrorAction Stop
        $result = winget --version 2>$null
        if ($result -and $result -match "v\d+\.\d+") {
            return $true
        }
        return $false
    }
    catch {
        return $false
    }
}

function Get-AppInstallerPackage {
    <#
    .SYNOPSIS
    Gets information about the App Installer package
    #>
    try {
        return Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -ErrorAction Stop
    }
    catch {
        return $null
    }
}

function Install-WingetFromStore {
    <#
    .SYNOPSIS
    Attempts to install winget via Microsoft Store
    #>
    Write-Host "Attempting to install winget via Microsoft Store..." -ForegroundColor Blue

    try {
        # Try to install via PowerShell Gallery first (if available)
        if (Get-Module -ListAvailable -Name Microsoft.WinGet.Client -ErrorAction SilentlyContinue) {
            Write-Host "Installing winget using Microsoft.WinGet.Client module..." -ForegroundColor Green
            Install-Module Microsoft.WinGet.Client -Force -AllowClobber
            Import-Module Microsoft.WinGet.Client
            return $true
        }

        # Fallback to direct download approach
        Write-Host "Downloading winget from GitHub releases..." -ForegroundColor Yellow

        # Get latest release info
        $apiUrl = "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
        $release = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing

        # Find the .msixbundle asset
        $asset = $release.assets | Where-Object { $_.name -like "*.msixbundle" } | Select-Object -First 1

        if (-not $asset) {
            throw "Could not find winget installer in latest release"
        }

        $downloadUrl = $asset.browser_download_url
        $tempPath = Join-Path $env:TEMP "Microsoft.DesktopAppInstaller.msixbundle"

        Write-Host "Downloading: $($asset.name)" -ForegroundColor Blue
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tempPath -UseBasicParsing

        # Install the package
        Write-Host "Installing App Installer package..." -ForegroundColor Blue
        Add-AppxPackage -Path $tempPath -ForceApplicationShutdown

        # Clean up
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue

        return $true
    }
    catch {
        Write-Error "Failed to install winget: $($_.Exception.Message)"
        return $false
    }
}

function Enable-WingetFeatures {
    <#
    .SYNOPSIS
    Enables necessary Windows features for winget
    #>
    Write-Host "Checking Windows features required for winget..." -ForegroundColor Blue

    # Check if we're on Windows 10 or 11
    $osVersion = [System.Environment]::OSVersion.Version
    if ($osVersion.Major -lt 10) {
        Write-Error "Windows 10 or later is required for winget"
        return $false
    }

    # For Windows 10, check build number
    if ($osVersion.Major -eq 10 -and $osVersion.Build -lt 17763) {
        Write-Error "Windows 10 build 1809 (17763) or later is required for winget"
        return $false
    }

    return $true
}

# Main script execution
Write-Host "=== Windows Package Manager (winget) Enablement Script ===" -ForegroundColor Cyan
Write-Host ""

# Check if Force parameter is used
if ($Force) {
    Write-Host "Force parameter specified - will reinstall winget" -ForegroundColor Yellow
    $wingetEnabled = $false
} else {
    # Check if winget is already available and working
    Write-Host "Checking if winget is available..." -ForegroundColor Blue
    $wingetEnabled = Test-WingetAvailable
}

if ($wingetEnabled) {
    $version = winget --version 2>$null
    Write-Host "✓ winget is already enabled and functional (Version: $version)" -ForegroundColor Green
    Write-Host ""
    Write-Host "Testing winget functionality..." -ForegroundColor Blue

    try {
        $testResult = winget list --count 1 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "✓ winget is working correctly" -ForegroundColor Green
            exit 0
        } else {
            Write-Warning "winget command exists but may not be functioning properly"
            $wingetEnabled = $false
        }
    }
    catch {
        Write-Warning "winget command exists but encountered an error during testing"
        $wingetEnabled = $false
    }
}

if (-not $wingetEnabled) {
    Write-Host "winget is not available or not functioning. Attempting to enable..." -ForegroundColor Yellow
    Write-Host ""

    # Check Windows version compatibility
    if (-not (Enable-WingetFeatures)) {
        exit 1
    }

    # Check current App Installer package status
    $appInstaller = Get-AppInstallerPackage
    if ($appInstaller) {
        Write-Host "App Installer package found: $($appInstaller.Version)" -ForegroundColor Blue
        if (-not $Force) {
            Write-Host "Attempting to repair App Installer package..." -ForegroundColor Blue
            try {
                # Try to reset the package
                Get-AppxPackage Microsoft.DesktopAppInstaller | Reset-AppxPackage
                Start-Sleep -Seconds 5

                if (Test-WingetAvailable) {
                    Write-Host "✓ winget has been successfully enabled!" -ForegroundColor Green
                    exit 0
                }
            }
            catch {
                Write-Warning "Failed to repair existing App Installer package: $($_.Exception.Message)"
            }
        }
    } else {
        Write-Host "App Installer package not found" -ForegroundColor Yellow
    }

    # Attempt to install winget
    Write-Host ""
    Write-Host "Installing winget..." -ForegroundColor Blue

    if (Install-WingetFromStore) {
        # Wait a moment for the installation to complete
        Write-Host "Waiting for installation to complete..." -ForegroundColor Blue
        Start-Sleep -Seconds 10

        # Test if winget is now available
        if (Test-WingetAvailable) {
            $version = winget --version 2>$null
            Write-Host ""
            Write-Host "✓ winget has been successfully enabled! (Version: $version)" -ForegroundColor Green

            # Test functionality
            Write-Host "Testing winget functionality..." -ForegroundColor Blue
            try {
                $testResult = winget list --count 1 2>$null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "✓ winget is working correctly" -ForegroundColor Green
                } else {
                    Write-Warning "winget was installed but may need additional configuration"
                }
            }
            catch {
                Write-Warning "winget was installed but encountered an error during testing"
            }
        } else {
            Write-Error "Installation appeared to succeed, but winget is still not available"
            Write-Host "You may need to:" -ForegroundColor Yellow
            Write-Host "  1. Restart your PowerShell session" -ForegroundColor Yellow
            Write-Host "  2. Install the App Installer manually from the Microsoft Store" -ForegroundColor Yellow
            Write-Host "  3. Restart your computer" -ForegroundColor Yellow
            exit 1
        }
    } else {
        Write-Error "Failed to install winget"
        Write-Host "Manual installation options:" -ForegroundColor Yellow
        Write-Host "  1. Install 'App Installer' from the Microsoft Store" -ForegroundColor Yellow
        Write-Host "  2. Download and install from: https://github.com/microsoft/winget-cli/releases" -ForegroundColor Yellow
        exit 1
    }
}

Write-Host ""
Write-Host "=== winget Enablement Complete ===" -ForegroundColor Cyan
