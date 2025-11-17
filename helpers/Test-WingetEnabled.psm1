<#
.SYNOPSIS
    Tests if Windows Package Manager (winget) is enabled and enables it if necessary.

.DESCRIPTION
    This script provides a simple way to check if winget is available and functional,
    and attempts to enable it if it's not already working.

.PARAMETER Quiet
    Suppresses informational output, only shows errors

.EXAMPLE
    .\Test-WingetEnabled.ps1
    Checks and enables winget with full output

.EXAMPLE
    .\Test-WingetEnabled.ps1 -Quiet
    Checks and enables winget silently

.OUTPUTS
    Returns $true if winget is enabled, $false otherwise

.NOTES
    Compatible with Windows 10 1809+ and Windows 11
    May require administrator privileges for installation
#>

[CmdletBinding()]
param(
    [switch]$Quiet
)

function Write-Info {
    param([string]$Message)
    if (-not $Quiet) {
        Write-Host $Message -ForegroundColor Blue
    }
}

function Write-Success {
    param([string]$Message)
    if (-not $Quiet) {
        Write-Host $Message -ForegroundColor Green
    }
}

function Write-Warn {
    param([string]$Message)
    if (-not $Quiet) {
        Write-Warning $Message
    }
}

function Test-WingetCommand {
    <#
    .SYNOPSIS
    Tests if winget command is available and functional
    #>
    try {
        $null = Get-Command winget -ErrorAction Stop
        $version = winget --version 2>$null
        if ($version -and $version -match "v\d+\.\d+") {
            # Test basic functionality
            $null = winget source list 2>$null
            return ($LASTEXITCODE -eq 0)
        }
        return $false
    }
    catch {
        return $false
    }
}

function Get-WingetPackage {
    <#
    .SYNOPSIS
    Gets the App Installer package information
    #>
    try {
        return Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -ErrorAction Stop
    }
    catch {
        return $null
    }
}

function Install-WingetPackage {
    <#
    .SYNOPSIS
    Installs winget via the App Installer package
    #>
    try {
        Write-Info "Downloading winget from Microsoft..."

        # Get the latest release from GitHub
        $releases = "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
        $response = Invoke-RestMethod -Uri $releases -UseBasicParsing

        # Find the msixbundle
        $asset = $response.assets | Where-Object { $_.name -like "*.msixbundle" } | Select-Object -First 1

        if (-not $asset) {
            throw "Could not find installer package"
        }

        $downloadPath = Join-Path $env:TEMP $asset.name
        Write-Info "Downloading $($asset.name)..."

        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $downloadPath -UseBasicParsing

        Write-Info "Installing App Installer package..."
        Add-AppxPackage -Path $downloadPath -ForceApplicationShutdown

        # Cleanup
        Remove-Item $downloadPath -Force -ErrorAction SilentlyContinue

        # Wait for installation
        Start-Sleep -Seconds 5

        return $true
    }
    catch {
        Write-Error "Failed to install winget: $($_.Exception.Message)"
        return $false
    }
}

function Enable-Winget {
    <#
    .SYNOPSIS
    Main function to enable winget
    #>

    # Check if already working
    if (Test-WingetCommand) {
        $version = winget --version 2>$null
        Write-Success "winget is already enabled (Version: $version)"
        return $true
    }

    Write-Info "winget not found or not functional, attempting to enable..."

    # Check if App Installer package exists but isn't working
    $appInstaller = Get-WingetPackage
    if ($appInstaller) {
        Write-Info "App Installer package found, attempting repair..."
        try {
            Get-AppxPackage Microsoft.DesktopAppInstaller | Reset-AppxPackage
            Start-Sleep -Seconds 3

            if (Test-WingetCommand) {
                Write-Success "winget has been repaired and is now functional"
                return $true
            }
        }
        catch {
            Write-Warn "Package repair failed, will attempt reinstallation"
        }
    }

    # Check if we have admin rights for installation
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

    if (-not $isAdmin) {
        Write-Error "Administrator privileges required to install winget. Please run as administrator."
        return $false
    }

    # Attempt installation
    if (Install-WingetPackage) {
        if (Test-WingetCommand) {
            $version = winget --version 2>$null
            Write-Success "winget has been successfully enabled (Version: $version)"
            return $true
        }
        else {
            Write-Error "Installation completed but winget is still not functional"
            return $false
        }
    }
    else {
        Write-Error "Failed to install winget"
        return $false
    }
}

# Main execution
try {
    $result = Enable-Winget
    if ($result) {
        if (-not $Quiet) {
            Write-Host "✓ winget is enabled and ready to use" -ForegroundColor Green
        }
        exit 0
    }
    else {
        Write-Host "✗ Failed to enable winget" -ForegroundColor Red
        Write-Host "Manual options:" -ForegroundColor Yellow
        Write-Host "  1. Install 'App Installer' from Microsoft Store" -ForegroundColor Yellow
        Write-Host "  2. Visit: https://github.com/microsoft/winget-cli/releases" -ForegroundColor Yellow
        exit 1
    }
}
catch {
    Write-Error "Unexpected error: $($_.Exception.Message)"
    exit 1
}

# Export functions for module usage
Export-ModuleMember -Function Enable-Winget, Test-WingetCommand, Get-WingetPackage, Install-WingetPackage
