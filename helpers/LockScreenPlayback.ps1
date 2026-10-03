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
# VIDEOCONLOCK is not part of compliance. This script does not rewrite the
# active power scheme. The reader below is diagnostic only: it parses the
# block after the VIDEOCONLOCK alias or GUID, and a missing block includes
# powercfg stdout in the error. Test and Set ignore that timeout.
#
# A failure here must not abort package installation. Set warns and returns.
#
# Chrome must be restarted before an already-open browser picks up the
# policy. Closing the lid, pressing the power button, or choosing Sleep
# still stops audio on Windows 11 Modern Standby.

Set-StrictMode -Version Latest

$script:ChromePolicySubKey = 'SOFTWARE\Policies\Google\Chrome'
$script:ChromePolicyName = 'WindowOcclusionEnabled'
$script:VideoSubgroup = 'SUB_VIDEO'
$script:ConsoleLockTimeoutSetting = 'VIDEOCONLOCK'
$script:ConsoleLockTimeoutGuid = '3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e'

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

    # /qh is scheme + subgroup only. The setting argument is ignored, so the
    # first AC/DC index in the subgroup is often a different video setting.
    $query = Invoke-PowerCfg -ArgumentList @(
        '/qh', 'SCHEME_CURRENT', $script:VideoSubgroup
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
        return (Get-ChromeWindowOcclusionPolicy) -eq 0
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

    try
    {
        if (Test-LockScreenPlayback)
        {
            return
        }

        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        $isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin)
        {
            Write-Warning 'Lock-screen playback settings require an elevated PowerShell session. Package configuration will continue.'
            return
        }

        Set-ChromeWindowOcclusionPolicy
    }
    catch
    {
        Write-Warning "Lock-screen playback was not applied. Package configuration will continue. $($_.Exception.Message)"
    }
}
