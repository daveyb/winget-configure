#Requires -Version 5.1
<#
.SYNOPSIS
    Install or update WSL via `wsl --update --web-download` and pin Microsoft.WSL.

.DESCRIPTION
    winget's Microsoft.WSL MSIX installer fails with 0x80073d28 when administrator
    privileges are required. `wsl.exe --update --web-download` pulls the same package
    from GitHub and succeeds in that situation.

    This module also adds a blocking winget pin for Microsoft.WSL so
    `winget upgrade --all` skips the broken MSIX path.
#>

Set-StrictMode -Version Latest

function Get-WslExePath
{
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $path = Join-Path $env:SystemRoot 'System32\wsl.exe'
    if (Test-Path -LiteralPath $path)
    {
        return $path
    }

    $cmd = Get-Command -Name 'wsl.exe' -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source)
    {
        return [string]$cmd.Source
    }

    return $null
}

function Get-InstalledWslVersion
{
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $wsl = Get-WslExePath
    if (-not $wsl)
    {
        return $null
    }

    try
    {
        $output = (& $wsl --version 2>&1 | Out-String) -replace "`0", ''
        if ($output -match 'WSL version:\s*(\S+)')
        {
            return $Matches[1].Trim()
        }
    }
    catch
    {
        return $null
    }

    return $null
}

function Test-WslWingetPin
{
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    try
    {
        $pins = & winget pin list --disable-interactivity 2>&1 | Out-String
        # Token match so Microsoft.WSLg / Microsoft.WSLPreview do not count.
        if ($pins -match '\bMicrosoft\.WSL\b')
        {
            return $true
        }
    }
    catch
    {
        return $false
    }

    return $false
}

function Add-WslWingetPin
{
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [switch]$Quiet
    )

    if (Test-WslWingetPin)
    {
        if (-not $Quiet)
        {
            Write-Host '[OK] Microsoft.WSL is already pinned' -ForegroundColor Green
        }
        return $true
    }

    if (-not $Quiet)
    {
        Write-Host '[...] Pinning Microsoft.WSL so winget upgrade --all skips it' -ForegroundColor Blue
    }

    $output = & winget pin add --id Microsoft.WSL --exact --blocking --disable-interactivity --accept-source-agreements 2>&1 | Out-String
    if (($LASTEXITCODE -eq 0) -or (Test-WslWingetPin))
    {
        if (-not $Quiet)
        {
            Write-Host '[OK] Pinned Microsoft.WSL (blocking)' -ForegroundColor Green
        }
        return $true
    }

    if (-not $Quiet)
    {
        Write-Warning "Could not pin Microsoft.WSL (exit $LASTEXITCODE). $output"
    }
    return $false
}

function Remove-WslWingetPin
{
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [switch]$Quiet
    )

    if (-not (Test-WslWingetPin))
    {
        return $true
    }

    $output = & winget pin remove --id Microsoft.WSL --exact --disable-interactivity 2>&1 | Out-String
    if (($LASTEXITCODE -eq 0) -or (-not (Test-WslWingetPin)))
    {
        if (-not $Quiet)
        {
            Write-Host '[OK] Removed Microsoft.WSL pin' -ForegroundColor Green
        }
        return $true
    }

    if (-not $Quiet)
    {
        Write-Warning "Could not remove Microsoft.WSL pin (exit $LASTEXITCODE). $output"
    }
    return $false
}

function Update-Wsl
{
    <#
    .SYNOPSIS
        Install or update WSL from GitHub, then pin Microsoft.WSL in winget.

    .PARAMETER SkipPin
        Do not add the blocking winget pin after a successful update.

    .PARAMETER Quiet
        Suppress informational output.
    #>
    [CmdletBinding()]
    param(
        [switch]$SkipPin,
        [switch]$Quiet
    )

    $result = @{
        Success = $false
        Message = ''
        Version = ''
    }

    $wsl = Get-WslExePath
    if (-not $wsl)
    {
        $result.Message = 'wsl.exe was not found under System32'
        if (-not $Quiet)
        {
            Write-Warning $result.Message
        }
        return $result
    }

    if (-not $Quiet)
    {
        Write-Host '[...] Updating WSL via wsl --update --web-download' -ForegroundColor Blue
    }

    $updateOutput = & $wsl --update --web-download 2>&1 | Out-String
    $updateCode = $LASTEXITCODE

    if ($updateCode -ne 0)
    {
        if (-not $Quiet)
        {
            Write-Host '[...] wsl --update failed; trying wsl --install --no-distribution --web-download' -ForegroundColor Blue
        }
        $updateOutput = & $wsl --install --no-distribution --web-download 2>&1 | Out-String
        $updateCode = $LASTEXITCODE
    }

    $result.Version = Get-InstalledWslVersion

    if ($updateCode -eq 0)
    {
        $result.Success = $true
        if ($updateOutput -match 'already installed')
        {
            $result.Message = 'WSL is already the most recent version'
        }
        else
        {
            $result.Message = 'WSL updated via web-download'
        }
        if (-not $Quiet)
        {
            $versionText = $result.Version
            if (-not $versionText)
            {
                $versionText = 'unknown'
            }
            $message = $result.Message
            Write-Host "[OK] $message (version $versionText)" -ForegroundColor Green
        }

        if (-not $SkipPin)
        {
            $null = Add-WslWingetPin -Quiet:$Quiet
        }

        return $result
    }

    $result.Message = "WSL web-download update failed (exit $updateCode). $updateOutput"
    if (-not $Quiet)
    {
        Write-Warning $result.Message
    }
    return $result
}

Export-ModuleMember -Function @(
    'Get-WslExePath',
    'Get-InstalledWslVersion',
    'Test-WslWingetPin',
    'Add-WslWingetPin',
    'Remove-WslWingetPin',
    'Update-Wsl'
)
