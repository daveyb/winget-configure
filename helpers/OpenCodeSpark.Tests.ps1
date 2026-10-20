#Requires -Version 7
$ErrorActionPreference = 'Stop'

$helper = Join-Path $PSScriptRoot 'OpenCodeSpark.ps1'
. $helper

function Assert-True
{
    param([bool]$Condition, [string]$Label)
    if (-not $Condition)
    {
        throw $Label
    }
}

function Assert-Equal
{
    param($Actual, $Expected, [string]$Label)
    if ($Actual -ne $Expected)
    {
        throw ("{0}. Expected [{1}] actual [{2}]" -f $Label, $Expected, $Actual)
    }
}

$launcherPath = Join-Path ([System.IO.Path]::GetTempPath()) ('opencode-spark-' + [guid]::NewGuid().ToString('n') + '.ps1')
$encoding = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($launcherPath, (Get-OpenCodeSparkLauncherText), $encoding)
try
{
    . $launcherPath

    function Format-OpenCodeSparkLaunch {
        param([string[]]$Argument)
        $launch = @(Get-OpenCodeSparkArgument -Argument $Argument)
        foreach ($item in $launch) {
            if ($item -isnot [string]) {
                throw 'launch argument is not a string'
            }
        }
        return ($launch -join '|')
    }

    Assert-Equal (Format-OpenCodeSparkLaunch) '--auto' 'no arguments'
    Assert-Equal (Format-OpenCodeSparkLaunch -Argument @('--version')) '--auto|--version' 'version flag stays on the default command'
    Assert-Equal (Format-OpenCodeSparkLaunch -Argument @('run')) 'run|--auto' 'run with no message'
    Assert-Equal (Format-OpenCodeSparkLaunch -Argument @('run', 'hello')) 'run|--auto|hello' 'run receives auto after the subcommand'
    Assert-Equal (Format-OpenCodeSparkLaunch -Argument @('--print-logs', 'run', 'hello')) '--print-logs|run|--auto|hello' 'run after a global flag still receives auto'
    Assert-Equal (Format-OpenCodeSparkLaunch -Argument @('-m', 'spark/x')) '--auto|-m|spark/x' 'tui model flag keeps a leading auto'
    Assert-Equal (Format-OpenCodeSparkLaunch -Argument @('C:\src')) '--auto|C:\src' 'project path keeps a leading auto'
    Assert-Equal (Format-OpenCodeSparkLaunch -Argument @('models')) 'models' 'models is unchanged'
    Assert-Equal (Format-OpenCodeSparkLaunch -Argument @('--print-logs', 'models')) '--print-logs|models' 'models after a global flag is unchanged'
    Assert-Equal (Format-OpenCodeSparkLaunch -Argument @('--auto', 'run')) '--auto|run' 'existing auto is kept'
    Assert-Equal (Format-OpenCodeSparkLaunch -Argument @('run', '--no-auto')) 'run|--no-auto' 'no-auto is kept'
    Assert-Equal (Format-OpenCodeSparkLaunch -Argument @('--no-auto')) '--no-auto' 'no-auto alone is kept'
}
finally
{
    Remove-Item -LiteralPath $launcherPath -Force -ErrorAction SilentlyContinue
}

$script:OpenCodeSparkCachePath = Join-Path ([System.IO.Path]::GetTempPath()) ('opencode-spark-missing-' + [guid]::NewGuid().ToString('n') + '.json')
$script:OpenCodeSparkDesiredReady = $false
$separator = [System.IO.Path]::DirectorySeparatorChar
$executableSuffix = "opencode-cli$separator$script:OpenCodeSparkVersion-x64$separator" + 'opencode.exe'
Assert-True ((Get-OpenCodeSparkExecutablePath).EndsWith($executableSuffix)) 'executable path uses the cached or pinned folder'
$launcherText = Get-OpenCodeSparkLauncherText
$versionFolder = 'opencode-cli\' + $script:OpenCodeSparkVersion + '-x64\opencode.exe'
Assert-True ($launcherText.Contains('Join-Path $env:LOCALAPPDATA')) 'launcher resolves the runtime profile'
Assert-True ($launcherText.Contains($versionFolder)) 'launcher names the pinned version folder'
Assert-True (-not $launcherText.Contains('__OPENCODE_SPARK_VERSION__')) 'launcher version placeholder is replaced'
Assert-True (-not $launcherText.Contains('__OPENCODE_SPARK_EXECUTABLE__')) 'launcher path is not a leftover placeholder'
if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA))
{
    Assert-True (-not $launcherText.Contains($env:LOCALAPPDATA)) 'launcher does not bake the Set-time profile path'
}
Assert-True (Test-OpenCodeSparkHashEqual -Actual 'e4ce9117f55fc068414513789f8c7d1049f855d7518bb4e350b9170a3a20d8c3' -Expected 'E4CE9117F55FC068414513789F8C7D1049F855D7518BB4E350B9170A3A20D8C3') 'zip hash compare ignores case'
Assert-True (-not (Test-OpenCodeSparkHashEqual -Actual '0000000000000000000000000000000000000000000000000000000000000000' -Expected 'E4CE9117F55FC068414513789F8C7D1049F855D7518BB4E350B9170A3A20D8C3')) 'zip hash compare rejects a different hash'
Assert-True (Test-OpenCodeSparkVersionOutput "$script:OpenCodeSparkVersion`r`n") 'version output accepts resolved version'
Assert-True (-not (Test-OpenCodeSparkVersionOutput '1.19.1')) 'version output rejects 1.19.1'

Assert-Equal $script:OpenCodeSparkVersion $script:OpenCodeSparkPinnedVersion 'dot-source keeps the pinned version'
Assert-Equal $script:OpenCodeSparkZipSha256 $script:OpenCodeSparkPinnedZipSha256 'dot-source keeps the pinned digest'
$helperText = [System.IO.File]::ReadAllText($helper)
$beforeFunctions = $helperText.Substring(0, $helperText.IndexOf('function '))
Assert-True (-not $beforeFunctions.Contains('Invoke-RestMethod')) 'parse does not call GitHub'
Assert-True (-not $helperText.Contains('TrimStart')) 'tag strip is not TrimStart'
Assert-True (-not $helperText.Contains("eq 'latest'")) 'dead latest branch is gone'
Assert-True (-not $helperText.Contains('Fallback to a known good version')) 'silent 1.19.3 fallback is gone'
Assert-True ($helperText.Contains('Test-OpenCodeSparkCacheFresh')) 'Test consults cache freshness'
Assert-True ($helperText.Contains('Join-Path $env:LOCALAPPDATA')) 'launcher template uses the runtime profile'
Assert-Equal $script:OpenCodeSparkCacheTtlHours 24 'cache TTL is 24 hours'
$headers = Get-OpenCodeSparkGitHubHeaders
Assert-True (-not [string]::IsNullOrWhiteSpace([string]$headers['User-Agent'])) 'GitHub request sends a User-Agent'
Assert-Equal (Compare-OpenCodeSparkVersion -Left '1.19.3' -Right '1.20.0') -1 'older version compares low'
Assert-Equal (Compare-OpenCodeSparkVersion -Left '1.20.0' -Right '1.19.3') 1 'newer version compares high'
Assert-Equal (Compare-OpenCodeSparkVersion -Left '1.19.3' -Right '1.19.3') 0 'same version compares equal'

function New-OpenCodeSparkReleaseFixture
{
    param(
        [string]$Tag,
        [string]$Url,
        [string]$Digest,
        [string]$Name = 'opencode-windows-x64.zip'
    )

    return [pscustomobject]@{
        tag_name = $Tag
        assets   = @(
            [pscustomobject]@{
                name                 = $Name
                browser_download_url = $Url
                digest               = $Digest
            }
        )
    }
}

function Assert-OpenCodeSparkThrows
{
    param([scriptblock]$Script, [string]$Label)

    $threw = $false
    try
    {
        & $Script | Out-Null
    }
    catch
    {
        $threw = $true
    }

    Assert-True $threw $Label
}

$resolved = ConvertTo-OpenCodeSparkRelease -Release (New-OpenCodeSparkReleaseFixture -Tag 'v1.20.0' -Url 'https://github.com/anomalyco/opencode/releases/download/v1.20.0/opencode-windows-x64.zip' -Digest 'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')
Assert-Equal $resolved.Version '1.20.0' 'release version strips one leading v'
Assert-Equal $resolved.Uri 'https://github.com/anomalyco/opencode/releases/download/v1.20.0/opencode-windows-x64.zip' 'release uses the asset URL'
Assert-Equal $resolved.Sha256 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' 'release keeps the asset digest'
Assert-OpenCodeSparkThrows { ConvertTo-OpenCodeSparkRelease -Release (New-OpenCodeSparkReleaseFixture -Tag 'vv1.19.3' -Url 'https://github.com/anomalyco/opencode/releases/download/v1.19.3/opencode-windows-x64.zip' -Digest 'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa') } 'TrimStart tag vv1.19.3 is rejected'
Assert-OpenCodeSparkThrows { ConvertTo-OpenCodeSparkRelease -Release (New-OpenCodeSparkReleaseFixture -Tag 'version-1.2.3' -Url 'https://github.com/anomalyco/opencode/releases/download/v1.2.3/opencode-windows-x64.zip' -Digest 'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa') } 'TrimStart tag version-1.2.3 is rejected'
Assert-OpenCodeSparkThrows { ConvertTo-OpenCodeSparkRelease -Release (New-OpenCodeSparkReleaseFixture -Tag 'v1.20.0' -Url 'https://github.com/anomalyco/opencode/releases/download/v1.20.0/opencode-windows-x64.zip' -Digest 'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' -Name 'opencode-windows-arm64.zip') } 'missing x64 asset is rejected'
Assert-OpenCodeSparkThrows { ConvertTo-OpenCodeSparkRelease -Release (New-OpenCodeSparkReleaseFixture -Tag 'v1.20.0' -Url 'https://github.com/anomalyco/opencode/releases/download/v1.20.0/opencode-windows-x64.zip' -Digest '') } 'missing digest is rejected'
Assert-OpenCodeSparkThrows { ConvertTo-OpenCodeSparkRelease -Release (New-OpenCodeSparkReleaseFixture -Tag 'v1.20.0' -Url 'https://example.test/opencode-windows-x64.zip' -Digest 'sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa') } 'asset host example.test is rejected'
Assert-OpenCodeSparkThrows { Set-OpenCodeSparkRelease -Version '1.20.0' -Uri 'https://example.test/opencode-windows-x64.zip' -Sha256 '   ' } 'empty hash is not confirmed'
Assert-True (Test-OpenCodeSparkAssetHost -Uri 'https://github.com/anomalyco/opencode/releases/download/v1.19.3/opencode-windows-x64.zip') 'github.com asset host is allowlisted'
Assert-True (Test-OpenCodeSparkAssetHost -Uri 'https://objects.githubusercontent.com/github-production-release-asset/opencode-windows-x64.zip') 'objects.githubusercontent.com asset host is allowlisted'
Assert-True (-not (Test-OpenCodeSparkAssetHost -Uri 'https://release-assets.githubusercontent.com/asset')) 'release-assets is not an asset URL host'
Assert-True (Test-OpenCodeSparkAssetHost -Uri 'https://release-assets.githubusercontent.com/asset' -Redirect) 'release-assets is an allowlisted redirect'
Assert-True (-not (Test-OpenCodeSparkAssetHost -Uri 'http://github.com/anomalyco/opencode/releases/download/v1.19.3/opencode-windows-x64.zip')) 'http asset host is rejected'
Assert-True (-not (Test-OpenCodeSparkAssetHost -Uri 'https://example.test/opencode-windows-x64.zip')) 'example.test asset host is rejected'
Assert-True (-not $helperText.Contains('Invoke-WebRequest')) 'asset download does not call Invoke-WebRequest'

$savedLocalAppData = $env:LOCALAPPDATA
$installRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('opencode-spark-installed-' + [guid]::NewGuid().ToString('n'))
$installedDir = Join-Path (Join-Path $installRoot 'opencode-cli') '1.20.0-x64'
New-Item -ItemType Directory -Path $installedDir -Force | Out-Null
New-Item -ItemType File -Path (Join-Path $installedDir 'opencode.exe') -Force | Out-Null
$env:LOCALAPPDATA = $installRoot
try
{
    Assert-Equal (Get-OpenCodeSparkNewestInstalledVersion) '1.20.0' 'installed version scan sees the newest exe'
}
finally
{
    $env:LOCALAPPDATA = $savedLocalAppData
    Remove-Item -LiteralPath $installRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$cacheRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('opencode-spark-cache-' + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $cacheRoot -Force | Out-Null
$script:OpenCodeSparkCachePath = Join-Path $cacheRoot 'release.json'
Set-OpenCodeSparkRelease -Version '1.20.0' -Uri 'https://example.test/opencode-windows-x64.zip' -Sha256 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
Write-OpenCodeSparkCache
$written = [System.IO.File]::ReadAllText($script:OpenCodeSparkCachePath) | ConvertFrom-Json
Assert-True (-not [string]::IsNullOrWhiteSpace([string]$written.fetched_at)) 'cache records fetched_at'
Assert-True (Test-OpenCodeSparkCacheFresh) 'cache written by Set is fresh'
$script:OpenCodeSparkDesiredReady = $false
$script:OpenCodeSparkVersion = '1.19.3'
Initialize-OpenCodeSparkDesired
Assert-Equal $script:OpenCodeSparkVersion '1.20.0' 'cache restores the verified release'
Assert-Equal $script:OpenCodeSparkZipSha256 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' 'cache restores the verified digest'
$cachedFolder = 'opencode-cli\1.20.0-x64\opencode.exe'
Assert-True ((Get-OpenCodeSparkLauncherText).Contains('Join-Path $env:LOCALAPPDATA')) 'cached launcher uses the runtime profile'
Assert-True ((Get-OpenCodeSparkLauncherText).Contains($cachedFolder)) 'launcher path is built from the cached version'
Remove-Item -LiteralPath $cacheRoot -Recurse -Force -ErrorAction SilentlyContinue
$script:OpenCodeSparkCachePath = Join-Path ([System.IO.Path]::GetTempPath()) ('opencode-spark-missing-' + [guid]::NewGuid().ToString('n') + '.json')
$script:OpenCodeSparkDesiredReady = $false
Initialize-OpenCodeSparkDesired

Set-StrictMode -Version Latest
$helperText = [System.IO.File]::ReadAllText($helper)
$dscGet = [scriptblock]::Create($helperText + "`nreturn (Get-OpenCodeSparkReport)`n")
$dscReport = & $dscGet
Assert-True ($null -ne $dscReport -and $dscReport.Result -match '^launcher=(present|missing);shim=(present|missing);path=(present|missing);opencode=(present|missing)$') 'strict scriptblock get returns facts'
Assert-True ($dscReport.Result -notmatch 'LITELLM|secret|pass://') 'report does not include a secret'

$freshRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('opencode-spark-fresh-' + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $freshRoot -Force | Out-Null
$script:OpenCodeSparkCachePath = Join-Path $freshRoot 'release.json'
try
{
    Assert-True (-not (Test-OpenCodeSparkCacheFresh)) 'missing release.json is not fresh'
    Assert-True (-not (Test-OpenCodeSpark)) 'Test is false when release.json is missing'

    $cacheRecord = @{
        version = '1.20.0'
        uri     = 'https://example.test/opencode-windows-x64.zip'
        sha256  = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
    }
    $cacheEncoding = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($script:OpenCodeSparkCachePath, ($cacheRecord | ConvertTo-Json -Compress), $cacheEncoding)
    Assert-True (-not (Test-OpenCodeSparkCacheFresh)) 'cache without fetched_at is stale'
    Assert-True (-not (Test-OpenCodeSpark)) 'Test is false when the cached release has no timestamp'

    $cacheRecord.fetched_at = [datetime]::UtcNow.AddHours(-25).ToString('o')
    [System.IO.File]::WriteAllText($script:OpenCodeSparkCachePath, ($cacheRecord | ConvertTo-Json -Compress), $cacheEncoding)
    Assert-True (-not (Test-OpenCodeSparkCacheFresh)) 'cache older than 24 hours is stale'
    Assert-True (-not (Test-OpenCodeSpark)) 'Test is false when the cached release is stale'

    $cacheRecord.fetched_at = [datetime]::UtcNow.AddHours(1).ToString('o')
    [System.IO.File]::WriteAllText($script:OpenCodeSparkCachePath, ($cacheRecord | ConvertTo-Json -Compress), $cacheEncoding)
    Assert-True (-not (Test-OpenCodeSparkCacheFresh)) 'a future cache timestamp is not fresh'

    $cacheRecord.fetched_at = [datetime]::UtcNow.AddMinutes(-5).ToString('o')
    [System.IO.File]::WriteAllText($script:OpenCodeSparkCachePath, ($cacheRecord | ConvertTo-Json -Compress), $cacheEncoding)
    Assert-True (Test-OpenCodeSparkCacheFresh) 'cache inside 24 hours is fresh'
}
finally
{
    Remove-Item -LiteralPath $freshRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$treeRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('opencode-spark-tree-' + [guid]::NewGuid().ToString('n'))
$treeVersionDir = Join-Path (Join-Path $treeRoot 'opencode-cli') '1.19.3-x64'
New-Item -ItemType Directory -Path $treeVersionDir -Force | Out-Null
New-Item -ItemType File -Path (Join-Path $treeVersionDir 'opencode.exe') -Force | Out-Null
$savedTreeLocal = $env:LOCALAPPDATA
$env:LOCALAPPDATA = $treeRoot
$script:OpenCodeSparkCachePath = Join-Path (Join-Path $treeRoot 'opencode-cli') 'release.json'
try
{
    $pinSha = $script:OpenCodeSparkPinnedZipSha256
    Assert-True (-not (Test-OpenCodeSparkInstalledRelease -Version '1.19.3' -Sha256 $pinSha)) 'installed tree without release.json does not match'
    $treeRecord = @{
        version    = '1.19.3'
        uri        = $script:OpenCodeSparkPinnedZipUri
        sha256     = $pinSha
        fetched_at = [datetime]::UtcNow.AddHours(-25).ToString('o')
    }
    $treeEncoding = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($script:OpenCodeSparkCachePath, ($treeRecord | ConvertTo-Json -Compress), $treeEncoding)
    Assert-True (Test-OpenCodeSparkInstalledRelease -Version '1.19.3' -Sha256 $pinSha) 'stale cache still matches the installed tree'
    Assert-True (Test-OpenCodeSparkReleaseInstallable -Version '1.19.3' -Sha256 $pinSha) 'matching installed tree is not replaced'
    Assert-True (-not (Test-OpenCodeSparkInstalledRelease -Version '1.19.3' -Sha256 ('B' * 64))) 'installed tree rejects a different digest'
    Assert-True (-not (Test-OpenCodeSparkReleaseInstallable -Version '1.20.0' -Sha256 ('B' * 64))) 'unpinned digest is not installable'
    Assert-True (Test-OpenCodeSparkReleaseInstallable -Version '1.20.0' -Sha256 $pinSha) 'pin digest remains the install authorization'
}
finally
{
    $env:LOCALAPPDATA = $savedTreeLocal
    Remove-Item -LiteralPath $treeRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output 'OpenCodeSpark tests passed'
