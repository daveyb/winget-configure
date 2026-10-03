# Lock-screen playback desired state for winget configure.
#
# Pocket Casts on this PC is the Chrome app. While the session is locked or
# the display is off, Chrome marks every window occluded and suspends it,
# which pauses playback. Chrome policy WindowOcclusionEnabled = 0 disables
# that detection.
#
# The policy is written to HKLM\SOFTWARE\Policies\Google\Chrome. winget
# configure runs elevated, and HKCU\Software\Policies is not writable by the
# signed-in user. Chrome applies this machine policy to every user.
#
# VIDEOCONLOCK is the console lock display-off timeout, in seconds. This
# script resets that timeout to 30 seconds on AC and on battery. It does
# not leave the lock screen on.
#
# Chrome must be restarted before an already-open browser picks up the
# policy. Closing the lid, pressing the power button, or choosing Sleep
# still stops audio on Windows 11 Modern Standby.

Set-StrictMode -Version Latest

$script:ChromePolicyKey = 'HKLM:\SOFTWARE\Policies\Google\Chrome'
$script:ChromePolicyName = 'WindowOcclusionEnabled'
$script:LockDisplayOffTimeoutSeconds = 30
$script:VideoSubgroup = 'SUB_VIDEO'
$script:ConsoleLockTimeoutSetting = 'VIDEOCONLOCK'

function Invoke-PowerCfg
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$ArgumentList
    )

    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    $output = & powercfg @ArgumentList 2>&1 | Out-String
    $code = $LASTEXITCODE
    $ErrorActionPreference = $saved

    return @{
        Output   = $output
        ExitCode = $code
    }
}

function Get-ConsoleLockDisplayOffTimeout
{
    [CmdletBinding()]
    param()

    # /query hides VIDEOCONLOCK. /qh returns the current AC and DC indexes.
    $query = Invoke-PowerCfg -ArgumentList @(
        '/qh', 'SCHEME_CURRENT', $script:VideoSubgroup, $script:ConsoleLockTimeoutSetting
    )

    $ac = $null
    $dc = $null
    if ($query.Output -match 'AC Power Setting Index:\s*0x([0-9A-Fa-f]+)')
    {
        $ac = [Convert]::ToInt32($Matches[1], 16)
    }
    if ($query.Output -match 'DC Power Setting Index:\s*0x([0-9A-Fa-f]+)')
    {
        $dc = [Convert]::ToInt32($Matches[1], 16)
    }

    return @{
        AcSeconds = $ac
        DcSeconds = $dc
        ExitCode  = $query.ExitCode
    }
}

function Get-ChromeWindowOcclusionPolicy
{
    [CmdletBinding()]
    param()

    if (-not (Test-Path -LiteralPath $script:ChromePolicyKey))
    {
        return $null
    }

    $prop = Get-ItemProperty -Path $script:ChromePolicyKey -Name $script:ChromePolicyName -ErrorAction SilentlyContinue
    if ($null -eq $prop)
    {
        return $null
    }

    $named = $prop.PSObject.Properties[$script:ChromePolicyName]
    if ($null -eq $named)
    {
        return $null
    }

    return [int]$named.Value
}

function Get-LockScreenPlaybackReport
{
    [CmdletBinding()]
    param()

    $timeout = Get-ConsoleLockDisplayOffTimeout
    $occlusion = Get-ChromeWindowOcclusionPolicy

    $occlusionText = if ($null -eq $occlusion) { 'unset' } else { [string]$occlusion }
    $acText = if ($null -eq $timeout.AcSeconds) { 'unset' } else { [string]$timeout.AcSeconds }
    $dcText = if ($null -eq $timeout.DcSeconds) { 'unset' } else { [string]$timeout.DcSeconds }

    return @{
        Result = "occlusion=$occlusionText;acSeconds=$acText;dcSeconds=$dcText"
    }
}

function Test-LockScreenPlayback
{
    [CmdletBinding()]
    param()

    $occlusion = Get-ChromeWindowOcclusionPolicy
    if ($occlusion -ne 0)
    {
        return $false
    }

    $timeout = Get-ConsoleLockDisplayOffTimeout
    if ($timeout.AcSeconds -ne $script:LockDisplayOffTimeoutSeconds)
    {
        return $false
    }
    if ($timeout.DcSeconds -ne $script:LockDisplayOffTimeoutSeconds)
    {
        return $false
    }

    return $true
}

function Set-LockScreenPlayback
{
    [CmdletBinding()]
    param()

    if (Test-LockScreenPlayback)
    {
        return
    }

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin)
    {
        throw 'Lock-screen playback settings require an elevated PowerShell session.'
    }

    if ((Get-ChromeWindowOcclusionPolicy) -ne 0)
    {
        New-Item -Path $script:ChromePolicyKey -Force | Out-Null
        New-ItemProperty -Path $script:ChromePolicyKey -Name $script:ChromePolicyName -PropertyType DWord -Value 0 -Force | Out-Null
    }

    $timeout = Get-ConsoleLockDisplayOffTimeout
    $timeoutChanged = $false
    $seconds = [string]$script:LockDisplayOffTimeoutSeconds

    if ($timeout.AcSeconds -ne $script:LockDisplayOffTimeoutSeconds)
    {
        $ac = Invoke-PowerCfg -ArgumentList @(
            '/setacvalueindex', 'SCHEME_CURRENT', $script:VideoSubgroup, $script:ConsoleLockTimeoutSetting, $seconds
        )
        if ($ac.ExitCode -ne 0)
        {
            throw "powercfg failed to set the AC console lock display timeout (exit $($ac.ExitCode))."
        }
        $timeoutChanged = $true
    }

    if ($timeout.DcSeconds -ne $script:LockDisplayOffTimeoutSeconds)
    {
        $dc = Invoke-PowerCfg -ArgumentList @(
            '/setdcvalueindex', 'SCHEME_CURRENT', $script:VideoSubgroup, $script:ConsoleLockTimeoutSetting, $seconds
        )
        if ($dc.ExitCode -ne 0)
        {
            throw "powercfg failed to set the battery console lock display timeout (exit $($dc.ExitCode))."
        }
        $timeoutChanged = $true
    }

    if ($timeoutChanged)
    {
        $active = Invoke-PowerCfg -ArgumentList @('/setactive', 'SCHEME_CURRENT')
        if ($active.ExitCode -ne 0)
        {
            throw "powercfg failed to activate the current power scheme (exit $($active.ExitCode))."
        }
    }

    if (-not (Test-LockScreenPlayback))
    {
        throw 'Lock-screen playback settings were not applied.'
    }
}
