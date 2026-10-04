# Lock-screen playback desired state for winget configure.
#
# Pocket Casts on this PC is the Chrome app. While the session is locked or
# the display is off, Chrome marks every window occluded and suspends it,
# which pauses playback. Chrome policy WindowOcclusionEnabled = 0 disables
# that detection.
#
# The policy is written to HKLM\SOFTWARE\Policies\Google\Chrome in the
# 64-bit registry view. CreateSubKey creates the Google and Chrome keys
# when they are missing. The elevated lock-screen process writes that
# policy. winget configure itself stays a normal window. Chrome applies
# this machine policy to every user. This script does not remove the value
# later.
#
# VIDEOCONLOCK (8ec4b3a5-6868-48c2-be75-4f3044be88a7) is the console lock
# display-off timeout, in seconds. This script resets it to 30 seconds on
# AC and on battery. powercfg /qh is queried for that setting only, and the
# current AC and DC indexes are the last two hex values in its block.
#
# Set shows a User Account Control prompt when the current process is not
# elevated, then applies the writes from that elevated process. Do not mark
# this resource securityContext elevated, and do not run the whole
# winget configure command as Administrator. That fails WinGetPackage with
# "Failed to create instance." Install-Packages.ps1 catches a dismissed
# prompt and continues with packages.
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

function Test-IsElevatedSession
{
    [CmdletBinding()]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-LockScreenPlaybackWorkerScript
{
    [CmdletBinding()]
    param()

    $functionNames = @(
        'Invoke-PowerCfg',
        'Get-PowerCfgSettingBlock',
        'Get-ConsoleLockDisplayOffTimeout',
        'Open-ChromePolicyHive',
        'Get-ChromeWindowOcclusionPolicy',
        'Set-ChromeWindowOcclusionPolicy',
        'Get-LockScreenPlaybackReport',
        'Test-LockScreenPlayback',
        'Test-IsElevatedSession',
        'Set-LockScreenPlayback'
    )

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.AppendLine('param([Parameter(Mandatory)][string]$ResultPath)')
    [void]$builder.AppendLine('$ErrorActionPreference = ''Stop''')
    [void]$builder.AppendLine('Set-StrictMode -Version Latest')
    [void]$builder.AppendLine('$env:LOCK_SCREEN_PLAYBACK_WORKER = ''1''')
    [void]$builder.AppendLine("`$script:ChromePolicySubKey = '$($script:ChromePolicySubKey)'")
    [void]$builder.AppendLine("`$script:ChromePolicyName = '$($script:ChromePolicyName)'")
    [void]$builder.AppendLine("`$script:VideoSubgroup = '$($script:VideoSubgroup)'")
    [void]$builder.AppendLine("`$script:ConsoleLockTimeoutSetting = '$($script:ConsoleLockTimeoutSetting)'")
    [void]$builder.AppendLine("`$script:ConsoleLockTimeoutGuid = '$($script:ConsoleLockTimeoutGuid)'")
    [void]$builder.AppendLine("`$script:LockDisplayOffTimeoutSeconds = $($script:LockDisplayOffTimeoutSeconds)")
    foreach ($functionName in $functionNames)
    {
        $command = Get-Command -Name $functionName -CommandType Function
        [void]$builder.AppendLine($command.ScriptBlock.Ast.Extent.Text)
        [void]$builder.AppendLine()
    }
    [void]$builder.AppendLine('try {')
    [void]$builder.AppendLine('    Set-LockScreenPlayback')
    [void]$builder.AppendLine('    if (-not (Test-LockScreenPlayback)) { throw ''Lock-screen playback settings were not applied.'' }')
    [void]$builder.AppendLine('    Set-Content -LiteralPath $ResultPath -Value ''OK'' -Encoding ASCII')
    [void]$builder.AppendLine('    exit 0')
    [void]$builder.AppendLine('}')
    [void]$builder.AppendLine('catch {')
    [void]$builder.AppendLine('    Set-Content -LiteralPath $ResultPath -Value $_.Exception.Message -Encoding ASCII')
    [void]$builder.AppendLine('    exit 1')
    [void]$builder.AppendLine('}')
    return $builder.ToString()
}

function Get-LockScreenPlaybackHostPath
{
    [CmdletBinding()]
    param()

    # Use the current process only when it is PowerShell. winget configure
    # runs this script in its configuration host, which cannot execute -File.
    $current = $null
    try
    {
        $current = (Get-Process -Id $PID -ErrorAction Stop).Path
    }
    catch
    {
        $current = $null
    }

    if (-not [string]::IsNullOrWhiteSpace($current))
    {
        $leaf = [System.IO.Path]::GetFileName($current)
        if ($leaf -eq 'powershell.exe' -or $leaf -eq 'pwsh.exe')
        {
            return $current
        }
    }

    return (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
}

function ConvertTo-LockScreenPlaybackArgument
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    # UseShellExecute takes one command line. Quote every path, including
    # those with no spaces, so TEMP values are not split.
    return '"' + $Value.Replace('"', '""') + '"'
}

function Read-LockScreenPlaybackResult
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    try
    {
        if (-not (Test-Path -LiteralPath $Path))
        {
            return ''
        }

        $text = Get-Content -LiteralPath $Path -Raw -ErrorAction SilentlyContinue
    }
    catch
    {
        return ''
    }

    if ($null -eq $text)
    {
        return ''
    }

    return ([string]$text).Trim()
}

function Start-LockScreenPlaybackElevated
{
    [CmdletBinding()]
    param()

    $directory = Join-Path $env:TEMP ("LockScreenPlayback-" + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Path $directory | Out-Null
    $scriptPath = Join-Path $directory 'apply.ps1'
    $resultPath = Join-Path $directory 'result.txt'
    $hostPath = Get-LockScreenPlaybackHostPath
    Set-Content -LiteralPath $scriptPath -Value (Get-LockScreenPlaybackWorkerScript) -Encoding ASCII

    # -Verb RunAs forces UseShellExecute. An argument array is split on
    # spaces, and $env:TEMP often contains spaces. Pass one quoted string.
    $arguments = @(
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        (ConvertTo-LockScreenPlaybackArgument $scriptPath)
        '-ResultPath'
        (ConvertTo-LockScreenPlaybackArgument $resultPath)
    ) -join ' '

    $handleMessage = $null
    $process = $null
    # A RunAs handle often cannot see the elevated process. Do not delete
    # apply.ps1 until that process has written the result file, or the
    # deadline has passed.
    $mayDelete = $false
    try
    {
        try
        {
            $process = Start-Process -FilePath $hostPath -ArgumentList $arguments -Verb RunAs -PassThru
        }
        catch
        {
            $handleMessage = $_.Exception.Message
        }

        if ($null -eq $process -and [string]::IsNullOrWhiteSpace($handleMessage))
        {
            $handleMessage = 'Lock-screen playback did not start the elevated PowerShell process.'
        }

        if ($null -eq $process)
        {
            # Nothing is writing. A dismissed consent prompt never starts the worker.
            $mayDelete = $true
            if ($handleMessage -match 'canceled by the user')
            {
                throw 'Lock-screen playback settings require an elevated PowerShell session. Approve the administrator prompt.'
            }

            throw "Lock-screen playback settings were not applied. $handleMessage"
        }

        # Poll until the result file is non-empty or the deadline passes.
        # WaitForExit can return immediately while pwsh is still starting or
        # still running powercfg. That is not completion and not failure.
        # Do not read ExitCode.
        $deadline = [datetime]::UtcNow.AddMinutes(10)
        $result = ''
        while ([datetime]::UtcNow -lt $deadline)
        {
            $result = Read-LockScreenPlaybackResult -Path $resultPath
            if (-not [string]::IsNullOrWhiteSpace($result))
            {
                break
            }

            try
            {
                # A false early exit must not end the wait, and must not busy-spin.
                if ($process.WaitForExit(500))
                {
                    Start-Sleep -Milliseconds 500
                }
            }
            catch
            {
                Start-Sleep -Milliseconds 500
            }
        }

        if ([string]::IsNullOrWhiteSpace($result))
        {
            $result = Read-LockScreenPlaybackResult -Path $resultPath
        }

        $mayDelete = $true

        if ($result -eq 'OK')
        {
            return
        }

        if ([string]::IsNullOrWhiteSpace($result))
        {
            throw 'Lock-screen playback settings were not applied.'
        }

        throw "Lock-screen playback settings were not applied. $result"
    }
    finally
    {
        if ($mayDelete)
        {
            Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction SilentlyContinue
        }
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

    if (-not (Test-IsElevatedSession))
    {
        if ($env:LOCK_SCREEN_PLAYBACK_WORKER -eq '1')
        {
            throw 'Lock-screen playback settings require an elevated PowerShell session. Approve the administrator prompt.'
        }

        Start-LockScreenPlaybackElevated
        if (-not (Test-LockScreenPlayback))
        {
            throw 'Lock-screen playback settings were not applied.'
        }
        return
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
