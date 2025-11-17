<#
.SYNOPSIS
    Ensures Windows Package Manager (winget) is available and functional.

.DESCRIPTION
    This script provides a simple function to detect if winget is enabled and
    attempts to enable it if necessary. Designed to be imported into other scripts.

.EXAMPLE
    . .\Ensure-Winget.ps1
    Ensure-Winget

.EXAMPLE
    if (Ensure-Winget -Quiet) {
        winget install SomeApp
    }

.NOTES
    Compatible with Windows 10 1809+ and Windows 11
    Requires administrator privileges for installation
#>

function Ensure-Winget {
    <#
    .SYNOPSIS
    Ensures winget is available and functional

    .PARAMETER Quiet
    Suppresses output except for errors

    .OUTPUTS
    Returns $true if winget is available, $false otherwise
    #>
    [CmdletBinding()]
    param(
        [switch]$Quiet
    )

    # Test if winget is already working
    try {
        $null = Get-Command winget -ErrorAction Stop
        $version = winget --version 2>$null
        if ($version -match "v\d+\.\d+") {
            # Quick functionality test
            winget source list >$null 2>&1
            if ($LASTEXITCODE -eq 0) {
                if (-not $Quiet) {
                    Write-Host "✓ winget is available (Version: $version)" -ForegroundColor Green
                }
                return $true
            }
        }
    }
    catch {
        # winget command not found, continue to installation
    }

    if (-not $Quiet) {
        Write-Host "winget not detected or not functional, attempting to enable..." -ForegroundColor Yellow
    }

    # Check if running as administrator
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

    if (-not $isAdmin) {
        Write-Error "Administrator privileges required to install winget"
        return $false
    }

    # Check Windows version compatibility
    $osVersion = [System.Environment]::OSVersion.Version
    if ($osVersion.Major -lt 10 -or ($osVersion.Major -eq 10 -and $osVersion.Build -lt 17763)) {
        Write-Error "Windows 10 build 1809 or later is required for winget"
        return $false
    }

    # Try to repair existing App Installer package first
    try {
        $appInstaller = Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -ErrorAction SilentlyContinue
        if ($appInstaller) {
            if (-not $Quiet) {
                Write-Host "Attempting to repair existing App Installer package..." -ForegroundColor Blue
            }
            $appInstaller | Reset-AppxPackage
            Start-Sleep -Seconds 3

            # Test again
            if (Test-WingetFunctionality) {
                if (-not $Quiet) {
                    Write-Host "✓ winget repaired successfully" -ForegroundColor Green
                }
                return $true
            }
        }
    }
    catch {
        # Continue to installation
    }

    # Install winget from GitHub releases
    try {
        if (-not $Quiet) {
            Write-Host "Downloading winget installer..." -ForegroundColor Blue
        }

        # Get latest release
        $apiUrl = "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
        $release = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing

        # Find msixbundle
        $asset = $release.assets | Where-Object { $_.name -like "*.msixbundle" } | Select-Object -First 1

        if (-not $asset) {
            throw "Could not find winget installer in latest release"
        }

        $tempPath = Join-Path $env:TEMP $asset.name
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tempPath -UseBasicParsing

        if (-not $Quiet) {
            Write-Host "Installing App Installer package..." -ForegroundColor Blue
        }

        Add-AppxPackage -Path $tempPath -ForceApplicationShutdown
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue

        # Wait for installation to complete
        Start-Sleep -Seconds 5

        # Final test
        if (Test-WingetFunctionality) {
            $version = winget --version 2>$null
            if (-not $Quiet) {
                Write-Host "✓ winget successfully installed (Version: $version)" -ForegroundColor Green
            }
            return $true
        }
        else {
            Write-Error "Installation completed but winget is not functional"
            return $false
        }
    }
    catch {
        Write-Error "Failed to install winget: $($_.Exception.Message)"
        return $false
    }
}

function Test-WingetFunctionality {
    <#
    .SYNOPSIS
    Helper function to test winget functionality
    #>
    try {
        $null = Get-Command winget -ErrorAction Stop
        winget source list >$null 2>&1
        return ($LASTEXITCODE -eq 0)
    }
    catch {
        return $false
    }
}

# Export functions for module usage
Export-ModuleMember -Function Ensure-Winget, Test-WingetFunctionality
