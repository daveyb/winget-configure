# Lock-screen playback desired state for winget configure.
#
# Pocket Casts on this PC is the Chrome app. While the session is locked or
# the display is off, Chrome marks every window occluded and suspends it,
# which pauses playback. Chrome policy WindowOcclusionEnabled = 0 disables
# that detection.
#
# The policy is written to HKLM\SOFTWARE\Policies\Google\Chrome in the
# 64-bit registry view. CreateSubKey creates the Google and Chrome keys
# when they are missing. winget configure runs elevated. Chrome applies
# this machine policy to every user. This script does not remove the value
# later.
#
# VIDEOCONLOCK (8ec4b3a5-6868-48c2-be75-4f3044be88a7) is the console lock
# display-off timeout, in seconds. This script resets it to 30 seconds on
# AC and on battery. powercfg /qh is queried for that setting only, and the
# current AC and DC indexes are the last two hex values in its block.
#
# The generated resource sets securityContext to elevated, so winget
# configure runs Set in an elevated process and prompts when the current
# window is not elevated. Set still throws when that process is not
# elevated or the write does not stick. Install-Packages.ps1 catches that
# and continues with packages.
#
# Chrome must be restarted before an already-open browser picks up the
# policy. Closing the lid, pressing the power button, or choosing Sleep
# still stops audio on Windows 11 Modern Standby.

Set-StrictMode -Version Latest

$script:ChromePolicySubKey = 'SOFTWARE\Policies\Google\Chrome'
$script:ChromePolicyName = 'WindowOcclusionEnabled'
$script:VideoSubgroup = 'SUB_VIDEO'
$script:ConsoleLockTimeoutSetting = 'VIDEOCONLOCK'
$script:ConsoleLockTimeoutGuid = '8ec4b3a5-6868-48c2-be75-4f3044be88a7'
$script:LockDisplayOffTimeoutSeconds = 30

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

function Get-PowerCfgSettingBlock
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Output,

        [Parameter(Mandatory)]
        [string]$Alias,

        [Parameter(Mandatory)]
        [string]$Guid
    )

    $lines = @($Output -split '\r?\n')
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++)
    {
        $line = $lines[$i]
        if ($line -match [regex]::Escape($Guid) -or $line -match ('(?i)\b' + [regex]::Escape($Alias) + '\b'))
        {
            $start = $i
            break
        }
    }

    if ($start -lt 0)
    {
        return $null
    }

    $block = New-Object System.Collections.Generic.List[string]
    $block.Add($lines[$start]) | Out-Null
    for ($j = $start + 1; $j -lt $lines.Count; $j++)
    {
        $line = $lines[$j]
        $otherGuid = $line -match '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}'
        if ($otherGuid -and $line -notmatch [regex]::Escape($Guid))
        {
            break
        }

        $block.Add($line) | Out-Null
    }

    return ($block -join "`n")
}

function Get-ConsoleLockDisplayOffTimeout
{
    [CmdletBinding()]
    param()

    # Ask for VIDEOCONLOCK itself. A subgroup-wide /qh lists other display
    # settings first, and their indexes are not this timeout.
    $query = Invoke-PowerCfg -ArgumentList @(
        '/qh', 'SCHEME_CURRENT', $script:VideoSubgroup, $script:ConsoleLockTimeoutGuid
    )
    $stdout = [string]$query.Output
    if ($null -eq $query.ExitCode -or $query.ExitCode -ne 0)
    {
        throw "powercfg /qh failed (exit $($query.ExitCode)).`n$stdout"
    }

    $block = Get-PowerCfgSettingBlock -Output $stdout -Alias $script:ConsoleLockTimeoutSetting -Guid $script:ConsoleLockTimeoutGuid
    if ([string]::IsNullOrWhiteSpace($block))
    {
        throw "powercfg /qh did not include a $($script:ConsoleLockTimeoutSetting) block.`n$stdout"
    }

    # Labels are localized. Within this setting the last two hex values are
    # the current AC and DC indexes (earlier values are minimum, maximum,
    # and increment).
    $indexes = @(
        [regex]::Matches($block, '(?m):\s*0x([0-9A-Fa-f]+)\s*$') |
            ForEach-Object { [Convert]::ToInt64($_.Groups[1].Value, 16) }
    )
    if ($indexes.Count -lt 2)
    {
        throw "powercfg /qh $($script:ConsoleLockTimeoutSetting) block has no AC/DC indexes.`n$stdout"
    }

    return @{
        AcSeconds = $indexes[$indexes.Count - 2]
        DcSeconds = $indexes[$indexes.Count - 1]
        ExitCode  = $query.ExitCode
    }
}

function Open-ChromePolicyHive
{
    [CmdletBinding()]
    param()

    return [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::LocalMachine,
        [Microsoft.Win32.RegistryView]::Registry64)
}

function Get-ChromeWindowOcclusionPolicy
{
    [CmdletBinding()]
    param()

    $base = Open-ChromePolicyHive
    try
    {
        $key = $base.OpenSubKey($script:ChromePolicySubKey)
        if ($null -eq $key)
        {
            return $null
        }

        try
        {
            $value = $key.GetValue($script:ChromePolicyName, $null)
            if ($null -eq $value)
            {
                return $null
            }

            return [int]$value
        }
        finally
        {
            $key.Dispose()
        }
    }
    finally
    {
        $base.Dispose()
    }
}

function Set-ChromeWindowOcclusionPolicy
{
    [CmdletBinding()]
    param()

    $base = Open-ChromePolicyHive
    try
    {
        # CreateSubKey creates Policies\Google\Chrome when those keys are missing.
        $key = $base.CreateSubKey($script:ChromePolicySubKey)
        try
        {
            $key.SetValue(
                $script:ChromePolicyName,
                0,
                [Microsoft.Win32.RegistryValueKind]::DWord)
        }
        finally
        {
            if ($null -ne $key)
            {
                $key.Dispose()
            }
        }
    }
    finally
    {
        $base.Dispose()
    }
}

function Get-LockScreenPlaybackReport
{
    [CmdletBinding()]
    param()

    $occlusionText = 'unset'
    try
    {
        $occlusion = Get-ChromeWindowOcclusionPolicy
        if ($null -ne $occlusion)
        {
            $occlusionText = [string]$occlusion
        }
    }
    catch
    {
        $occlusionText = "error:$($_.Exception.Message)"
    }

    $acText = 'unread'
    $dcText = 'unread'
    try
    {
        $timeout = Get-ConsoleLockDisplayOffTimeout
        $acText = if ($null -eq $timeout.AcSeconds) { 'unset' } else { [string]$timeout.AcSeconds }
        $dcText = if ($null -eq $timeout.DcSeconds) { 'unset' } else { [string]$timeout.DcSeconds }
    }
    catch
    {
        $acText = "error:$($_.Exception.Message)"
        $dcText = $acText
    }

    return @{
        Result = "occlusion=$occlusionText;acSeconds=$acText;dcSeconds=$dcText"
    }
}

function Test-LockScreenPlayback
{
    [CmdletBinding()]
    param()

    try
    {
        if ((Get-ChromeWindowOcclusionPolicy) -ne 0)
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
    catch
    {
        return $false
    }
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
        Set-ChromeWindowOcclusionPolicy
    }

    $timeout = Get-ConsoleLockDisplayOffTimeout
    $timeoutChanged = $false
    $seconds = [string]$script:LockDisplayOffTimeoutSeconds

    if ($timeout.AcSeconds -ne $script:LockDisplayOffTimeoutSeconds)
    {
        $ac = Invoke-PowerCfg -ArgumentList @(
            '/setacvalueindex', 'SCHEME_CURRENT', $script:VideoSubgroup, $script:ConsoleLockTimeoutGuid, $seconds
        )
        if ($ac.ExitCode -ne 0)
        {
            throw "powercfg failed to set the AC console lock display timeout (exit $($ac.ExitCode)).`n$($ac.Output)"
        }
        $timeoutChanged = $true
    }

    if ($timeout.DcSeconds -ne $script:LockDisplayOffTimeoutSeconds)
    {
        $dc = Invoke-PowerCfg -ArgumentList @(
            '/setdcvalueindex', 'SCHEME_CURRENT', $script:VideoSubgroup, $script:ConsoleLockTimeoutGuid, $seconds
        )
        if ($dc.ExitCode -ne 0)
        {
            throw "powercfg failed to set the battery console lock display timeout (exit $($dc.ExitCode)).`n$($dc.Output)"
        }
        $timeoutChanged = $true
    }

    if ($timeoutChanged)
    {
        $active = Invoke-PowerCfg -ArgumentList @('/setactive', 'SCHEME_CURRENT')
        if ($active.ExitCode -ne 0)
        {
            throw "powercfg failed to activate the current power scheme (exit $($active.ExitCode)).`n$($active.Output)"
        }
    }

    if (-not (Test-LockScreenPlayback))
    {
        throw 'Lock-screen playback settings were not applied.'
    }
}
