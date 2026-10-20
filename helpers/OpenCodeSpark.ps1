# winget configure can run this file under Windows PowerShell 5.1.
# File writes and the user Path work in that host, so this helper does not relaunch pwsh.
# The LiteLLM key is not stored. opencode-spark reads it from Proton Pass when it starts.

$ErrorActionPreference = 'Stop'

# Cached x64 zip. The winget ARM64 build cannot start the TUI.
# Get and Test use this pin, or release.json after Set has verified a release.
# Do not call GitHub while this file is parsed.
$script:OpenCodeSparkPinnedVersion = '1.19.3'
$script:OpenCodeSparkPinnedZipUri = 'https://github.com/anomalyco/opencode/releases/download/v1.19.3/opencode-windows-x64.zip'
$script:OpenCodeSparkPinnedZipSha256 = 'E4CE9117F55FC068414513789F8C7D1049F855D7518BB4E350B9170A3A20D8C3'
$script:OpenCodeSparkVersion = $script:OpenCodeSparkPinnedVersion
$script:OpenCodeSparkZipUri = $script:OpenCodeSparkPinnedZipUri
$script:OpenCodeSparkZipSha256 = $script:OpenCodeSparkPinnedZipSha256
$script:OpenCodeSparkDesiredReady = $false
$script:OpenCodeSparkCachePath = $null
$script:OpenCodeSparkAssetName = 'opencode-windows-x64.zip'

function Get-OpenCodeSparkGitHubHeaders
{
    [CmdletBinding()]
    param()

    return @{
        'User-Agent'           = 'winget-configure'
        'Accept'               = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
    }
}

function Compare-OpenCodeSparkVersion
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Left,
        [Parameter(Mandatory)][string]$Right
    )

    $leftParts = $Left.Split('.')
    $rightParts = $Right.Split('.')
    if ($leftParts.Count -ne 3 -or $rightParts.Count -ne 3)
    {
        throw "OpenCode version was not a three-part number: $Left $Right"
    }

    for ($i = 0; $i -lt 3; $i++)
    {
        $leftNumber = 0
        $rightNumber = 0
        if (-not [int]::TryParse($leftParts[$i], [ref]$leftNumber) -or -not [int]::TryParse($rightParts[$i], [ref]$rightNumber))
        {
            throw "OpenCode version was not a three-part number: $Left $Right"
        }

        if ($leftNumber -lt $rightNumber)
        {
            return -1
        }

        if ($leftNumber -gt $rightNumber)
        {
            return 1
        }
    }

    return 0
}

function ConvertTo-OpenCodeSparkRelease
{
    [CmdletBinding()]
    param($Release)

    if ($null -eq $Release)
    {
        throw 'OpenCode release was not returned'
    }

    $tag = [string]$Release.tag_name
    $version = $null
    if ($tag -match '^v(\d+\.\d+\.\d+)$')
    {
        $version = $Matches[1]
    }
    else
    {
        throw "OpenCode release tag was $tag"
    }

    $asset = $null
    foreach ($item in @($Release.assets))
    {
        if ($null -eq $item)
        {
            continue
        }

        if ([string]$item.name -eq $script:OpenCodeSparkAssetName)
        {
            $asset = $item
            break
        }
    }

    if ($null -eq $asset)
    {
        throw "OpenCode release has no $($script:OpenCodeSparkAssetName) asset"
    }

    $uri = [string]$asset.browser_download_url
    if ([string]::IsNullOrWhiteSpace($uri))
    {
        throw 'OpenCode asset URL was empty'
    }

    $digest = [string]$asset.digest
    $sha256 = $null
    if ($digest -match '^sha256:([A-Fa-f0-9]{64})$')
    {
        $sha256 = $Matches[1]
    }
    else
    {
        throw 'OpenCode asset digest was missing'
    }

    return @{
        Version = $version
        Uri     = $uri
        Sha256  = $sha256
    }
}

function Get-OpenCodeSparkCachePath
{
    [CmdletBinding()]
    param()

    if (-not [string]::IsNullOrWhiteSpace($script:OpenCodeSparkCachePath))
    {
        return $script:OpenCodeSparkCachePath
    }

    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA))
    {
        return $null
    }

    return (Join-Path $env:LOCALAPPDATA 'opencode-cli\release.json')
}

function Initialize-OpenCodeSparkDesired
{
    [CmdletBinding()]
    param()

    if ($script:OpenCodeSparkDesiredReady)
    {
        return
    }

    $script:OpenCodeSparkVersion = $script:OpenCodeSparkPinnedVersion
    $script:OpenCodeSparkZipUri = $script:OpenCodeSparkPinnedZipUri
    $script:OpenCodeSparkZipSha256 = $script:OpenCodeSparkPinnedZipSha256

    $cachePath = Get-OpenCodeSparkCachePath
    if ($cachePath -and (Test-Path -LiteralPath $cachePath -PathType Leaf))
    {
        try
        {
            $cached = [System.IO.File]::ReadAllText($cachePath) | ConvertFrom-Json
            $version = [string]$cached.version
            $uri = [string]$cached.uri
            $sha = [string]$cached.sha256
            if ($version -match '^\d+\.\d+\.\d+$' -and -not [string]::IsNullOrWhiteSpace($uri) -and $sha -match '^[A-Fa-f0-9]{64}$')
            {
                $script:OpenCodeSparkVersion = $version
                $script:OpenCodeSparkZipUri = $uri
                $script:OpenCodeSparkZipSha256 = $sha.ToUpperInvariant()
            }
        }
        catch
        {
            $script:OpenCodeSparkVersion = $script:OpenCodeSparkPinnedVersion
            $script:OpenCodeSparkZipUri = $script:OpenCodeSparkPinnedZipUri
            $script:OpenCodeSparkZipSha256 = $script:OpenCodeSparkPinnedZipSha256
        }
    }

    $script:OpenCodeSparkDesiredReady = $true
}

function Set-OpenCodeSparkRelease
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Sha256
    )

    if ([string]::IsNullOrWhiteSpace($Sha256))
    {
        throw 'OpenCode zip hash was not confirmed'
    }

    $script:OpenCodeSparkVersion = $Version
    $script:OpenCodeSparkZipUri = $Uri
    $script:OpenCodeSparkZipSha256 = $Sha256
    $script:OpenCodeSparkDesiredReady = $true
}

function Write-OpenCodeSparkCache
{
    [CmdletBinding()]
    param()

    if ([string]::IsNullOrWhiteSpace($script:OpenCodeSparkZipSha256))
    {
        throw 'OpenCode zip hash was not confirmed'
    }

    $path = Get-OpenCodeSparkCachePath
    if ([string]::IsNullOrWhiteSpace($path))
    {
        throw 'OpenCode cache path is not available'
    }

    $directory = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $directory))
    {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $payload = @{
        version = $script:OpenCodeSparkVersion
        uri     = $script:OpenCodeSparkZipUri
        sha256  = $script:OpenCodeSparkZipSha256
    } | ConvertTo-Json -Compress

    $encoding = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($path, $payload, $encoding)
}

function Get-OpenCodeSparkNewestInstalledVersion
{
    [CmdletBinding()]
    param()

    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA))
    {
        return $null
    }

    $base = Join-Path $env:LOCALAPPDATA 'opencode-cli'
    if (-not (Test-Path -LiteralPath $base -PathType Container))
    {
        return $null
    }

    $newest = $null
    foreach ($dir in @(Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue))
    {
        if ($dir.Name -notmatch '^(\d+\.\d+\.\d+)-x64$')
        {
            continue
        }

        $version = $Matches[1]
        $exe = Join-Path $dir.FullName 'opencode.exe'
        if (-not (Test-Path -LiteralPath $exe -PathType Leaf))
        {
            continue
        }

        if ($null -eq $newest -or (Compare-OpenCodeSparkVersion -Left $version -Right $newest) -gt 0)
        {
            $newest = $version
        }
    }

    return $newest
}

function Resolve-OpenCodeSparkRelease
{
    [CmdletBinding()]
    param()

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $headers = Get-OpenCodeSparkGitHubHeaders
    $payload = Invoke-RestMethod -Uri 'https://api.github.com/repos/anomalyco/opencode/releases/latest' -Headers $headers -TimeoutSec 30 -ErrorAction Stop
    return (ConvertTo-OpenCodeSparkRelease -Release $payload)
}

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
    $opencode = '__OPENCODE_SPARK_EXECUTABLE__'
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

    Initialize-OpenCodeSparkDesired
    $text = $text.Replace('__OPENCODE_SPARK_EXECUTABLE__', (Get-OpenCodeSparkExecutablePath))

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

function Get-OpenCodeSparkExecutablePath
{
    [CmdletBinding()]
    param()

    Initialize-OpenCodeSparkDesired
    $folder = 'opencode-cli\' + $script:OpenCodeSparkVersion + '-x64'
    return (Join-Path $env:LOCALAPPDATA (Join-Path $folder 'opencode.exe'))
}

function Test-OpenCodeSparkHashEqual
{
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Actual,
        [AllowEmptyString()][string]$Expected
    )

    if ([string]::IsNullOrWhiteSpace($Actual) -or [string]::IsNullOrWhiteSpace($Expected))
    {
        return $false
    }

    return ($Actual.Trim().ToUpperInvariant() -eq $Expected.Trim().ToUpperInvariant())
}

function Test-OpenCodeSparkVersionOutput
{
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Text)

    $normalized = ($Text -replace "`0", '').Trim()
    return ($normalized -eq $script:OpenCodeSparkVersion)
}

function Get-OpenCodeSparkVersionOutput
{
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    try
    {
        $output = (& $Path --version 2>&1 | Out-String)
    }
    finally
    {
        $ErrorActionPreference = $saved
    }

    return ($output -replace "`0", '')
}

function Test-OpenCodeSparkExecutable
{
    [CmdletBinding()]
    param()

    $path = Get-OpenCodeSparkExecutablePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        return $false
    }

    return (Test-OpenCodeSparkVersionOutput (Get-OpenCodeSparkVersionOutput -Path $path))
}

function Install-OpenCodeSparkExecutable
{
    [CmdletBinding()]
    param()

    if (Test-OpenCodeSparkExecutable)
    {
        return
    }

    $destination = Get-OpenCodeSparkExecutablePath
    $temp = Join-Path $env:TEMP ('opencode-spark-' + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Path $temp -Force | Out-Null
    try
    {
        $zip = Join-Path $temp 'opencode-windows-x64.zip'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        if ([string]::IsNullOrWhiteSpace($script:OpenCodeSparkZipSha256))
        {
            throw 'OpenCode zip hash was not confirmed'
        }

        Invoke-WebRequest -Uri $script:OpenCodeSparkZipUri -OutFile $zip -UseBasicParsing
        $hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
        if (-not (Test-OpenCodeSparkHashEqual -Actual $hash -Expected $script:OpenCodeSparkZipSha256))
        {
            throw "OpenCode zip hash was $hash"
        }

        $extract = Join-Path $temp 'extract'
        Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
        $found = @(Get-ChildItem -LiteralPath $extract -Filter 'opencode.exe' -Recurse -File)
        if ($found.Count -lt 1)
        {
            throw 'OpenCode zip did not contain opencode.exe'
        }

        $directory = Split-Path -Parent $destination
        if (-not (Test-Path -LiteralPath $directory))
        {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }

        Copy-Item -LiteralPath $found[0].FullName -Destination $destination -Force
    }
    finally
    {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (-not (Test-OpenCodeSparkExecutable))
    {
        throw 'OpenCode executable was not installed.'
    }
}

function Get-OpenCodeSparkFacts
{
    [CmdletBinding()]
    param()

    $bin = Get-OpenCodeSparkBinDirectory
    return @{
        Launcher   = [bool](Test-OpenCodeSparkTextFile -Path (Join-Path $bin 'opencode-spark.ps1') -Desired (Get-OpenCodeSparkLauncherText))
        Shim       = [bool](Test-OpenCodeSparkTextFile -Path (Join-Path $bin 'opencode-spark.cmd') -Desired (Get-OpenCodeSparkCommandText))
        Path       = [bool](Test-OpenCodeSparkPathEntry)
        Executable = [bool](Test-OpenCodeSparkExecutable)
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
    $executableState = 'missing'
    if ($facts.Executable)
    {
        $executableState = 'present'
    }

    return @{
        Result = ('launcher={0};shim={1};path={2};opencode={3}' -f $launcherState, $shimState, $pathState, $executableState)
    }
}

function Test-OpenCodeSpark
{
    [CmdletBinding()]
    param()

    try
    {
        $facts = Get-OpenCodeSparkFacts
        return [bool]($facts.Launcher -and $facts.Shim -and $facts.Path -and $facts.Executable)
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

    Initialize-OpenCodeSparkDesired
    $cachedVersion = $script:OpenCodeSparkVersion
    $release = Resolve-OpenCodeSparkRelease
    if ((Compare-OpenCodeSparkVersion -Left $release.Version -Right $cachedVersion) -lt 0)
    {
        throw "OpenCode release $($release.Version) is older than cached $cachedVersion"
    }

    $installed = Get-OpenCodeSparkNewestInstalledVersion
    if ($installed -and (Compare-OpenCodeSparkVersion -Left $release.Version -Right $installed) -lt 0)
    {
        throw "OpenCode release $($release.Version) is older than installed $installed"
    }

    Set-OpenCodeSparkRelease -Version $release.Version -Uri $release.Uri -Sha256 $release.Sha256
    Install-OpenCodeSparkExecutable
    Write-OpenCodeSparkCache

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
    if (-not ($facts.Launcher -and $facts.Shim -and $facts.Path -and $facts.Executable))
    {
        throw 'opencode-spark launcher, command shim, user Path entry, or OpenCode executable was not applied.'
    }
}
