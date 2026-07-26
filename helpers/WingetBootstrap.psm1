#Requires -Version 5.1
<#
.SYNOPSIS
    Bootstrap helpers for Windows Package Manager (winget).

.DESCRIPTION
    Side-effect-free on import. Call Assert-WingetAvailable (or the
    Ensure-Winget alias) to detect, repair, or install winget.

.NOTES
    Compatible with Windows 10 1809+ and Windows 11.
    Administrator privileges are required to install or repair winget.
#>

Set-StrictMode -Version Latest

function Test-WingetAvailable
{
    <#
    .SYNOPSIS
        Returns $true if the winget CLI is present and functional.
    #>
    [CmdletBinding()]
    param()

    try
    {
        $null = Get-Command winget -ErrorAction Stop
        $version = & winget --version 2>$null
        if (-not ($version -and $version -match 'v\d+\.\d+'))
        {
            return $false
        }

        & winget source list >$null 2>&1
        return ($LASTEXITCODE -eq 0)
    }
    catch
    {
        return $false
    }
}

function Test-IsAdministrator
{
    [CmdletBinding()]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-WingetOsCompatible
{
    [CmdletBinding()]
    param()

    $osVersion = [System.Environment]::OSVersion.Version
    if ($osVersion.Major -lt 10)
    {
        return $false
    }
    if ($osVersion.Major -eq 10 -and $osVersion.Build -lt 17763)
    {
        return $false
    }
    return $true
}

function Repair-WingetAppInstaller
{
    <#
    .SYNOPSIS
        Attempts to reset the Desktop App Installer package.
    #>
    [CmdletBinding()]
    param()

    $appInstaller = Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' -ErrorAction SilentlyContinue
    if (-not $appInstaller)
    {
        return $false
    }

    $appInstaller | Reset-AppxPackage
    Start-Sleep -Seconds 3
    return (Test-WingetAvailable)
}

function Install-WingetAppInstaller
{
    <#
    .SYNOPSIS
        Downloads and installs the latest winget App Installer from GitHub releases.
    #>
    [CmdletBinding()]
    param()

    $apiUrl = 'https://api.github.com/repos/microsoft/winget-cli/releases/latest'
    $release = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing

    $asset = $release.assets | Where-Object { $_.name -like '*.msixbundle' } | Select-Object -First 1
    if (-not $asset)
    {
        throw 'Could not find winget installer (.msixbundle) in the latest GitHub release.'
    }

    $tempPath = Join-Path $env:TEMP $asset.name
    try
    {
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tempPath -UseBasicParsing
        Add-AppxPackage -Path $tempPath -ForceApplicationShutdown
    }
    finally
    {
        Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
    }

    Start-Sleep -Seconds 5
    return (Test-WingetAvailable)
}

function Assert-WingetAvailable
{
    <#
    .SYNOPSIS
        Ensures winget is available and functional, installing it if needed.

    .PARAMETER Quiet
        Suppresses informational output (errors still write).

    .OUTPUTS
        $true if winget is available; otherwise $false.
    #>
    [CmdletBinding()]
    param(
        [switch]$Quiet
    )

    if (Test-WingetAvailable)
    {
        if (-not $Quiet)
        {
            $version = & winget --version 2>$null
            Write-Host "[OK] winget is available (Version: $version)" -ForegroundColor Green
        }
        return $true
    }

    if (-not $Quiet)
    {
        Write-Host '[*] winget not detected or not functional, attempting to enable...' -ForegroundColor Yellow
    }

    if (-not (Test-WingetOsCompatible))
    {
        Write-Error 'Windows 10 build 1809 or later is required for winget.'
        return $false
    }

    if (-not (Test-IsAdministrator))
    {
        Write-Error 'Administrator privileges are required to install winget.'
        return $false
    }

    try
    {
        if (-not $Quiet)
        {
            Write-Host '[i] Attempting to repair existing App Installer package...' -ForegroundColor Blue
        }

        if (Repair-WingetAppInstaller)
        {
            if (-not $Quiet)
            {
                Write-Host '[OK] winget repaired successfully' -ForegroundColor Green
            }
            return $true
        }
    }
    catch
    {
        # Continue to full install
    }

    try
    {
        if (-not $Quiet)
        {
            Write-Host '[i] Downloading winget installer...' -ForegroundColor Blue
        }

        if (Install-WingetAppInstaller)
        {
            $version = & winget --version 2>$null
            if (-not $Quiet)
            {
                Write-Host "[OK] winget successfully installed (Version: $version)" -ForegroundColor Green
            }
            return $true
        }

        Write-Error 'Installation completed but winget is not functional.'
        return $false
    }
    catch
    {
        Write-Error "Failed to install winget: $($_.Exception.Message)"
        return $false
    }
}

# Back-compat alias used by Install-Packages.ps1 and existing docs
Set-Alias -Name Ensure-Winget -Value Assert-WingetAvailable

Export-ModuleMember -Function @(
    'Test-WingetAvailable'
    'Assert-WingetAvailable'
    'Repair-WingetAppInstaller'
    'Install-WingetAppInstaller'
    'Test-IsAdministrator'
    'Test-WingetOsCompatible'
) -Alias Ensure-Winget
