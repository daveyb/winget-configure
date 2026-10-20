# winget configure can run this file under Windows PowerShell 5.1.
# File writes and the user Path work in that host, so this helper does not relaunch pwsh.
# The LiteLLM key is not stored. opencode-spark reads it from Proton Pass when it starts.

$ErrorActionPreference = 'Stop'

function Get-OpenCodeSparkBinDirectory
{
    [CmdletBinding()]
    param()

    return (Join-Path $env:USERPROFILE '.local\bin')
}

function Get-OpenCodeSparkLauncherText
{
    [CmdletBinding()]
    param()

    $text = @'
# Starts OpenCode with the DGX Spark LiteLLM key in the environment.
# The key is read from Proton Pass and removed when OpenCode exits. It is not written to disk.
$ErrorActionPreference = 'Stop'

function Get-OpenCodeSparkArgument {
    param([string[]]$Argument)

    $given = @($Argument | Where-Object { $null -ne $_ -and $_ -ne '' })
    foreach ($item in $given) {
        if ($item -eq '--auto' -or $item -eq '--no-auto') {
            return $given
        }
    }

    # A leading --auto selects the default TUI command. `run` is a subcommand,
    # so --auto has to follow it. Other subcommands reject --auto.
    $commands = @(
        'completion', 'acp', 'mcp', 'attach', 'run', 'debug', 'providers', 'auth',
        'agent', 'upgrade', 'uninstall', 'serve', 'web', 'models', 'stats',
        'export', 'import', 'github', 'pr', 'session', 'plugin', 'plug', 'db'
    )
    $commandIndex = -1
    for ($i = 0; $i -lt $given.Count; $i++) {
        if (-not $given[$i].StartsWith('-')) {
            $commandIndex = $i
            break
        }
    }

    if ($commandIndex -ge 0 -and $given[$commandIndex] -eq 'run') {
        if ($commandIndex -gt 0) {
            $head = @($given[0..$commandIndex])
        }
        else {
            $head = @($given[0])
        }
        $tail = @()
        $next = $commandIndex + 1
        if ($next -lt $given.Count) {
            $tail = @($given[$next..($given.Count - 1)])
        }
        return ($head + @('--auto') + $tail)
    }

    if ($commandIndex -ge 0 -and ($commands -contains $given[$commandIndex])) {
        return $given
    }

    return (@('--auto') + $given)
}

function Invoke-OpenCodeSpark {
    param([string[]]$Argument)

    $pass = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\Proton.ProtonPass.CLI_Microsoft.Winget.Source_8wekyb3d8bbwe\pass-cli.exe'
    if (-not (Test-Path $pass)) {
        $cmd = Get-Command pass-cli -ErrorAction SilentlyContinue
        if (-not $cmd) { throw 'pass-cli is not installed' }
        $pass = $cmd.Source
    }

    # The winget ARM64 build cannot start the TUI. bun:ffi is disabled there.
    # The x64 build runs under emulation and the TUI comes up.
    $opencode = Join-Path $env:LOCALAPPDATA 'opencode-cli\1.19.3-x64\opencode.exe'
    if (-not (Test-Path $opencode)) {
        throw 'opencode x64 build is not installed'
    }

    # pass-cli run pipes the child. OpenCode's TUI then waits on that pipe and never draws.
    # Read the key and start OpenCode on this console instead.
    $secret = (& $pass item view --vault-name DGXSpark --item-title LITELLM_MASTER_KEY --field secret | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or $secret.Length -lt 20 -or $secret.StartsWith('pass://') -or $secret.StartsWith('Error')) {
        throw 'pass-cli could not read the LiteLLM master key'
    }
    $env:LITELLM_MASTER_KEY = $secret
    try {
        $launch = @(Get-OpenCodeSparkArgument -Argument $Argument)
        & $opencode @launch
        exit $LASTEXITCODE
    }
    finally {
        Remove-Item Env:\LITELLM_MASTER_KEY -ErrorAction SilentlyContinue
        Remove-Variable secret -ErrorAction SilentlyContinue
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-OpenCodeSpark -Argument $args
}
'@
    return ((ConvertTo-OpenCodeSparkText $text) + "`n")
}

function Get-OpenCodeSparkCommandText
{
    [CmdletBinding()]
    param()

    $text = @'
@echo off
pwsh -NoProfile -File "%~dp0opencode-spark.ps1" %*
'@
    return ((ConvertTo-OpenCodeSparkText $text) + "`n")
}

function ConvertTo-OpenCodeSparkText
{
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Text)

    if ($null -eq $Text)
    {
        return ''
    }

    $normalized = $Text -replace "`r`n", "`n" -replace "`r", "`n"
    return $normalized.TrimEnd("`n")
}

function Test-OpenCodeSparkTextFile
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Desired
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf))
    {
        return $false
    }

    $current = [System.IO.File]::ReadAllText($Path)
    return ((ConvertTo-OpenCodeSparkText $current) -eq (ConvertTo-OpenCodeSparkText $Desired))
}

function ConvertTo-OpenCodeSparkPathKey
{
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Entry)

    if ([string]::IsNullOrWhiteSpace($Entry))
    {
        return ''
    }

    return $Entry.Trim().TrimEnd('\', '/').ToLowerInvariant()
}

function Test-OpenCodeSparkPathEntry
{
    [CmdletBinding()]
    param()

    $binKey = ConvertTo-OpenCodeSparkPathKey (Get-OpenCodeSparkBinDirectory)
    if ($binKey -eq '')
    {
        return $false
    }

    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ([string]::IsNullOrWhiteSpace($current))
    {
        return $false
    }

    foreach ($entry in $current.Split(';'))
    {
        if ((ConvertTo-OpenCodeSparkPathKey $entry) -eq $binKey)
        {
            return $true
        }
    }

    return $false
}

function Get-OpenCodeSparkFacts
{
    [CmdletBinding()]
    param()

    $bin = Get-OpenCodeSparkBinDirectory
    return @{
        Launcher = [bool](Test-OpenCodeSparkTextFile -Path (Join-Path $bin 'opencode-spark.ps1') -Desired (Get-OpenCodeSparkLauncherText))
        Shim     = [bool](Test-OpenCodeSparkTextFile -Path (Join-Path $bin 'opencode-spark.cmd') -Desired (Get-OpenCodeSparkCommandText))
        Path     = [bool](Test-OpenCodeSparkPathEntry)
    }
}

function Set-OpenCodeSparkTextFile
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory))
    {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $encoding = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Path, $Text, $encoding)
}

function Get-OpenCodeSparkReport
{
    [CmdletBinding()]
    param()

    $facts = Get-OpenCodeSparkFacts
    $launcherState = 'missing'
    if ($facts.Launcher)
    {
        $launcherState = 'present'
    }
    $shimState = 'missing'
    if ($facts.Shim)
    {
        $shimState = 'present'
    }
    $pathState = 'missing'
    if ($facts.Path)
    {
        $pathState = 'present'
    }

    return @{
        Result = ('launcher={0};shim={1};path={2}' -f $launcherState, $shimState, $pathState)
    }
}

function Test-OpenCodeSpark
{
    [CmdletBinding()]
    param()

    try
    {
        $facts = Get-OpenCodeSparkFacts
        return [bool]($facts.Launcher -and $facts.Shim -and $facts.Path)
    }
    catch
    {
        return $false
    }
}

function Set-OpenCodeSpark
{
    [CmdletBinding()]
    param()

    $bin = Get-OpenCodeSparkBinDirectory
    Set-OpenCodeSparkTextFile -Path (Join-Path $bin 'opencode-spark.ps1') -Text (Get-OpenCodeSparkLauncherText)
    Set-OpenCodeSparkTextFile -Path (Join-Path $bin 'opencode-spark.cmd') -Text (Get-OpenCodeSparkCommandText)

    if (-not (Test-OpenCodeSparkPathEntry))
    {
        $current = [Environment]::GetEnvironmentVariable('Path', 'User')
        if ([string]::IsNullOrWhiteSpace($current))
        {
            $updated = $bin
        }
        else
        {
            $updated = $current + ';' + $bin
        }

        [Environment]::SetEnvironmentVariable('Path', $updated, 'User')
    }

    $facts = Get-OpenCodeSparkFacts
    if (-not ($facts.Launcher -and $facts.Shim -and $facts.Path))
    {
        throw 'opencode-spark launcher, command shim, or user Path entry was not applied.'
    }
}
