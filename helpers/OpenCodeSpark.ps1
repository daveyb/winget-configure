# winget configure can run this file under Windows PowerShell 5.1.
# File writes and the user Path work in that host, so this helper does not relaunch pwsh.
# The LiteLLM key is not stored. opencode-spark reads it from Proton Pass when it starts.

$ErrorActionPreference = 'Stop'

# Cached x64 zip. The winget ARM64 build cannot start the TUI.
# Get reads release.json after Set has verified a release, or this pin when
# that file is absent. Test is false when the cache is missing or older than
# OpenCodeSparkCacheTtlHours, so Set runs. Set refreshes fetched_at and does
# not replace opencode.exe when the resolved version and digest already match
# the installed tree. Set installs when the asset host is allowlisted and the
# zip hash matches the API digest. The pin does not block a later release.
# A leftover higher version folder is not a downgrade floor. Asset downloads
# are limited to GitHub hosts.
# Do not call GitHub while this file is parsed, and do not call it from Get or Test.
$script:OpenCodeSparkPinnedVersion = '1.19.3'
$script:OpenCodeSparkPinnedZipUri = 'https://github.com/anomalyco/opencode/releases/download/v1.19.3/opencode-windows-x64.zip'
$script:OpenCodeSparkPinnedZipSha256 = 'E4CE9117F55FC068414513789F8C7D1049F855D7518BB4E350B9170A3A20D8C3'
$script:OpenCodeSparkCacheTtlHours = 24
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

function Test-OpenCodeSparkAssetHost
{
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Uri,
        [switch]$Redirect
    )

    if ([string]::IsNullOrWhiteSpace($Uri))
    {
        return $false
    }

    $parsed = $null
    if (-not [uri]::TryCreate($Uri, [UriKind]::Absolute, [ref]$parsed))
    {
        return $false
    }

    if ($parsed.Scheme -ne 'https')
    {
        return $false
    }

    $hostName = $parsed.Host
    if ([string]::IsNullOrWhiteSpace($hostName))
    {
        return $false
    }

    $hostName = $hostName.ToLowerInvariant()
    if ($hostName -eq 'github.com' -or $hostName -eq 'objects.githubusercontent.com')
    {
        return $true
    }

    # GitHub's current release CDN. The asset URL itself stays on github.com
    # or objects.githubusercontent.com; only a redirect may land here.
    if ($Redirect -and $hostName -eq 'release-assets.githubusercontent.com')
    {
        return $true
    }

    return $false
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

    if (-not (Test-OpenCodeSparkAssetHost -Uri $uri))
    {
        throw "OpenCode asset host is not allowlisted: $uri"
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

function Read-OpenCodeSparkCache
{
    [CmdletBinding()]
    param()

    $path = Get-OpenCodeSparkCachePath
    if ([string]::IsNullOrWhiteSpace($path))
    {
        return $null
    }

    if (-not (Test-Path -LiteralPath $path -PathType Leaf))
    {
        return $null
    }

    try
    {
        $cached = [System.IO.File]::ReadAllText($path) | ConvertFrom-Json
        $version = [string]$cached.version
        $uri = [string]$cached.uri
        $sha = [string]$cached.sha256
        if ($version -notmatch '^\d+\.\d+\.\d+$' -or [string]::IsNullOrWhiteSpace($uri) -or $sha -notmatch '^[A-Fa-f0-9]{64}$')
        {
            return $null
        }

        $fetched = $null
        $rawFetched = ''
        $fetchedProperty = $cached.PSObject.Properties['fetched_at']
        if ($null -ne $fetchedProperty -and -not [string]::IsNullOrWhiteSpace([string]$fetchedProperty.Value))
        {
            $rawFetched = [string]$fetchedProperty.Value
            $parsed = [datetime]::MinValue
            $styles = [System.Globalization.DateTimeStyles]::RoundtripKind
            if ([datetime]::TryParse($rawFetched, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed))
            {
                if ($parsed.Kind -eq [System.DateTimeKind]::Unspecified)
                {
                    $parsed = [datetime]::SpecifyKind($parsed, [System.DateTimeKind]::Utc)
                }

                $fetched = $parsed.ToUniversalTime()
            }
        }

        return @{
            Version   = $version
            Uri       = $uri
            Sha256    = $sha.ToUpperInvariant()
            FetchedAt = $fetched
        }
    }
    catch
    {
        return $null
    }
}

function Test-OpenCodeSparkCacheFresh
{
    [CmdletBinding()]
    param()

    $cached = Read-OpenCodeSparkCache
    if ($null -eq $cached -or $null -eq $cached.FetchedAt)
    {
        return $false
    }

    $age = [datetime]::UtcNow - $cached.FetchedAt
    if ($age.TotalHours -lt 0)
    {
        return $false
    }

    return ($age.TotalHours -lt $script:OpenCodeSparkCacheTtlHours)
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

    $cached = Read-OpenCodeSparkCache
    if ($null -ne $cached)
    {
        $script:OpenCodeSparkVersion = $cached.Version
        $script:OpenCodeSparkZipUri = $cached.Uri
        $script:OpenCodeSparkZipSha256 = $cached.Sha256
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
        version    = $script:OpenCodeSparkVersion
        uri        = $script:OpenCodeSparkZipUri
        sha256     = $script:OpenCodeSparkZipSha256
        fetched_at = [datetime]::UtcNow.ToString('o')
    } | ConvertTo-Json -Compress

    $encoding = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($path, $payload, $encoding)
}

function Get-OpenCodeSparkSelectedInstalledVersion
{
    [CmdletBinding()]
    param()

    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA))
    {
        return $null
    }

    $cached = Read-OpenCodeSparkCache
    $version = $script:OpenCodeSparkPinnedVersion
    if ($null -ne $cached)
    {
        $version = $cached.Version
    }

    $exe = Join-Path (Join-Path (Join-Path $env:LOCALAPPDATA 'opencode-cli') ($version + '-x64')) 'opencode.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf))
    {
        return $null
    }

    return $version
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
    # Join LOCALAPPDATA at start so a moved profile is not stuck on the Set-time path.
    $opencode = Join-Path $env:LOCALAPPDATA 'opencode-cli\__OPENCODE_SPARK_VERSION__-x64\opencode.exe'
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
    $text = $text.Replace('__OPENCODE_SPARK_VERSION__', $script:OpenCodeSparkVersion)

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

function Save-OpenCodeSparkAsset
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$OutFile
    )

    if (-not (Test-OpenCodeSparkAssetHost -Uri $Uri))
    {
        throw "OpenCode asset host is not allowlisted: $Uri"
    }

    $current = $Uri
    for ($hop = 0; $hop -lt 5; $hop++)
    {
        $request = [System.Net.HttpWebRequest][System.Net.WebRequest]::Create($current)
        $request.Method = 'GET'
        $request.AllowAutoRedirect = $false
        $request.UserAgent = 'winget-configure'
        $request.Timeout = 300000
        $request.ReadWriteTimeout = 300000

        $response = $null
        try
        {
            $response = $request.GetResponse()
        }
        catch [System.Net.WebException]
        {
            $response = $_.Exception.Response
            if ($null -eq $response)
            {
                throw
            }
        }

        try
        {
            $status = [int]$response.StatusCode
            if ($status -ge 300 -and $status -lt 400)
            {
                $next = [string]$response.Headers['Location']
                if ([string]::IsNullOrWhiteSpace($next))
                {
                    throw 'OpenCode asset redirect was empty'
                }

                $nextUri = (New-Object System.Uri -ArgumentList ([uri]$current), $next).AbsoluteUri
                if (-not (Test-OpenCodeSparkAssetHost -Uri $nextUri -Redirect))
                {
                    throw "OpenCode asset redirect host is not allowlisted: $nextUri"
                }

                $current = $nextUri
                continue
            }

            if ($status -ne 200)
            {
                throw "OpenCode asset download returned $status"
            }

            $stream = $response.GetResponseStream()
            $file = [System.IO.File]::Create($OutFile)
            try
            {
                $stream.CopyTo($file)
            }
            finally
            {
                $file.Dispose()
                if ($null -ne $stream)
                {
                    $stream.Dispose()
                }
            }

            return
        }
        finally
        {
            if ($null -ne $response)
            {
                $response.Dispose()
            }
        }
    }

    throw 'OpenCode asset redirect limit exceeded'
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

        if (-not (Test-OpenCodeSparkAssetHost -Uri $script:OpenCodeSparkZipUri))
        {
            throw "OpenCode asset host is not allowlisted: $($script:OpenCodeSparkZipUri)"
        }

        Save-OpenCodeSparkAsset -Uri $script:OpenCodeSparkZipUri -OutFile $zip
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
        # DSC skips Set when this is true. A missing or stale cache must fail
        # here so Set fetches the current verified release. Do not call GitHub.
        if (-not (Test-OpenCodeSparkCacheFresh))
        {
            return $false
        }

        $facts = Get-OpenCodeSparkFacts
        return [bool]($facts.Launcher -and $facts.Shim -and $facts.Path -and $facts.Executable)
    }
    catch
    {
        return $false
    }
}

function Test-OpenCodeSparkInstalledRelease
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$Sha256
    )

    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA))
    {
        return $false
    }

    $folder = Join-Path (Join-Path $env:LOCALAPPDATA 'opencode-cli') ($Version + '-x64')
    $exe = Join-Path $folder 'opencode.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf))
    {
        return $false
    }

    $cached = Read-OpenCodeSparkCache
    if ($null -eq $cached)
    {
        return $false
    }

    if ($cached.Version -ne $Version)
    {
        return $false
    }

    return (Test-OpenCodeSparkHashEqual -Actual $cached.Sha256 -Expected $Sha256)
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

    $installed = Get-OpenCodeSparkSelectedInstalledVersion
    if ($installed -and (Compare-OpenCodeSparkVersion -Left $release.Version -Right $installed) -lt 0)
    {
        throw "OpenCode release $($release.Version) is older than installed $installed"
    }

    if (-not (Test-OpenCodeSparkAssetHost -Uri $release.Uri))
    {
        throw "OpenCode asset host is not allowlisted: $($release.Uri)"
    }

    $treeMatch = Test-OpenCodeSparkInstalledRelease -Version $release.Version -Sha256 $release.Sha256
    Set-OpenCodeSparkRelease -Version $release.Version -Uri $release.Uri -Sha256 $release.Sha256
    if (-not $treeMatch)
    {
        Install-OpenCodeSparkExecutable
    }

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
