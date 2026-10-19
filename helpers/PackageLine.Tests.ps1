#Requires -Version 7
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'PackageLine.ps1')

function Assert-Equal
{
    param($Actual, $Expected, [string]$Label)
    if ($Actual -cne $Expected)
    {
        throw ("{0}. Expected [{1}] actual [{2}]" -f $Label, $Expected, $Actual)
    }
}

function Assert-ThrowsToken
{
    param(
        [scriptblock]$Script,
        [string]$Token,
        [string]$Label
    )

    $threw = $false
    $message = ''
    try
    {
        & $Script | Out-Null
    }
    catch
    {
        $threw = $true
        $message = [string]$_.Exception.Message
    }
    if (-not $threw)
    {
        throw "$Label did not throw"
    }
    if (-not $message.Contains($Token))
    {
        throw ("{0}. Expected message to contain [{1}] actual [{2}]" -f $Label, $Token, $message)
    }
}

function Assert-DscPackage
{
    param(
        [string]$Yaml,
        [string]$Id,
        [string]$Source,
        [string]$Ensure,
        [string]$Label
    )

    $normalized = $Yaml -replace "`r`n", "`n" -replace "`r", "`n"
    $needle = "id: $Id`n        source: $Source`n        ensure: $Ensure"
    if (-not $normalized.Contains($needle))
    {
        throw ("{0}. Expected [{1}] in generated DSC" -f $Label, $needle)
    }
}

$git = ConvertFrom-PackageLine -Text '    - Git.Git # Git version control'
Assert-Equal $git.Id 'Git.Git' 'marked git id'
Assert-Equal $git.Source 'winget' 'marked git source'
Assert-Equal $git.Comment 'Git version control' 'marked git comment'

$vlc = ConvertFrom-PackageLine -Text '    - VideoLAN.VLC'
Assert-Equal $vlc.Id 'VideoLAN.VLC' 'vlc id'
Assert-Equal $vlc.Source 'winget' 'vlc source'
Assert-Equal $vlc.Comment '' 'vlc comment'

$store = ConvertFrom-PackageLine -Text '    - 9NCBCSZSJRSB source: msstore # Spotify (Microsoft Store)'
Assert-Equal $store.Id '9NCBCSZSJRSB' 'store id'
Assert-Equal $store.Source 'msstore' 'store source'
Assert-Equal $store.Comment 'Spotify (Microsoft Store)' 'store comment'

$bare = ConvertFrom-PackageLine -Text 'Git.Git'
Assert-Equal $bare.Id 'Git.Git' 'bare git id'
Assert-Equal $bare.Source 'winget' 'bare git source'
Assert-Equal $bare.Comment '' 'bare git comment'

$explicit = ConvertFrom-PackageLine -Text 'Git.Git source: winget'
Assert-Equal $explicit.Id 'Git.Git' 'explicit winget id'
Assert-Equal $explicit.Source 'winget' 'explicit winget source'
Assert-Equal $explicit.Comment '' 'explicit winget comment'

Assert-ThrowsToken { ConvertFrom-PackageLine -Text '9NCBCSZSJRSB source: MSStore' } 'MSStore' 'MSStore source'
Assert-ThrowsToken { ConvertFrom-PackageLine -Text '9NCBCSZSJRSB msstore' } 'msstore' 'bare msstore word'

$repoRoot = Split-Path -Parent $PSScriptRoot
$packagesFile = Join-Path $repoRoot 'winget-packages.yml'
$dscPath = Join-Path $repoRoot '.configurations\configuration.dsc.yaml'
$fixtureRoot = Join-Path $env:TEMP ('package-line-repo-' + [guid]::NewGuid().ToString('n'))
$fixtureYaml = Join-Path $fixtureRoot 'winget-packages.yml'
$outputPath = Join-Path $env:TEMP ('package-line-dsc-' + [guid]::NewGuid().ToString('n') + '.yaml')
$previous = @"
packages:
  development:
    - Git.Git # Git version control
  media_entertainment:
    - Spotify.Spotify # Spotify music streaming
    - Contoso.SourceMove source: winget # same id, old source
"@
$current = @"
packages:
  development:
    - Git.Git # Git version control
  media_entertainment:
    - 9NCBCSZSJRSB source: msstore # Spotify (Microsoft Store)
    - Contoso.SourceMove source: msstore # same id, new source
"@
if ($current.Contains('Spotify.Spotify'))
{
    throw 'current fixture contains Spotify.Spotify'
}
if (-not $previous.Contains('Spotify.Spotify'))
{
    throw 'previous fixture is missing Spotify.Spotify'
}
$utf8 = New-Object System.Text.UTF8Encoding $false

$dscBefore = $null
if (Test-Path -LiteralPath $dscPath)
{
    $dscBefore = [System.IO.File]::ReadAllBytes($dscPath)
}
$packagesBefore = [System.IO.File]::ReadAllBytes($packagesFile)

$gitEnvNames = @(
    'GIT_DIR',
    'GIT_WORK_TREE',
    'GIT_INDEX_FILE',
    'GIT_PREFIX',
    'GIT_COMMON_DIR',
    'GIT_OBJECT_DIRECTORY'
)
$savedGitEnv = @{}
foreach ($name in $gitEnvNames)
{
    $envPath = "Env:$name"
    if (Test-Path -LiteralPath $envPath)
    {
        $savedGitEnv[$name] = (Get-Item -LiteralPath $envPath).Value
        Remove-Item -LiteralPath $envPath
    }
}

try
{
    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
    $previousText = ($previous -replace "`r`n", "`n" -replace "`r", "`n") -replace "`n", "`r`n"
    $currentText = ($current -replace "`r`n", "`n" -replace "`r", "`n") -replace "`n", "`r`n"
    [System.IO.File]::WriteAllText($fixtureYaml, $previousText, $utf8)
    $PSNativeCommandUseErrorActionPreference = $false
    $init = & git -C $fixtureRoot init -b fixture 2>&1
    if ($LASTEXITCODE -ne 0)
    {
        throw ("git init exited {0}: {1}" -f $LASTEXITCODE, ($init | Out-String))
    }
    $add = & git -C $fixtureRoot add -- winget-packages.yml 2>&1
    if ($LASTEXITCODE -ne 0)
    {
        throw ("git add exited {0}: {1}" -f $LASTEXITCODE, ($add | Out-String))
    }
    $commit = & git -C $fixtureRoot -c user.name=fixture -c user.email=fixture@example.com -c commit.gpgsign=false commit -m 'previous packages' 2>&1
    if ($LASTEXITCODE -ne 0)
    {
        throw ("git commit exited {0}: {1}" -f $LASTEXITCODE, ($commit | Out-String))
    }
    $shown = & git -C $fixtureRoot --no-pager show HEAD:winget-packages.yml 2>&1
    $shownText = $shown | Out-String
    if ($LASTEXITCODE -ne 0 -or -not $shownText.Contains('Spotify.Spotify'))
    {
        throw ("fixture HEAD is missing Spotify.Spotify: {0}" -f $shownText)
    }
    [System.IO.File]::WriteAllText($fixtureYaml, $currentText, $utf8)

    $generator = Join-Path $repoRoot 'New-WingetConfiguration.ps1'
    $run = & pwsh -NoProfile -WorkingDirectory $fixtureRoot -File $generator -PackagesFile $fixtureYaml -OutputFile $outputPath -Force -CompareRef HEAD *>&1
    $code = $LASTEXITCODE
    $runText = $run | Out-String
    if ($code -ne 0)
    {
        throw ("New-WingetConfiguration.ps1 exited {0}: {1}" -f $code, $runText)
    }
    if ($runText -notmatch 'Comparing against:\s+HEAD:winget-packages\.yml(\s|$)')
    {
        throw ("generator compared against the wrong git path: {0}" -f $runText)
    }
    if (-not (Test-Path -LiteralPath $outputPath))
    {
        throw "New-WingetConfiguration.ps1 did not write $outputPath"
    }
    $generated = [System.IO.File]::ReadAllText($outputPath)
    $checks = @(
        @{ Id = '9NCBCSZSJRSB'; Source = 'msstore'; Ensure = 'Present'; Label = 'store present' },
        @{ Id = 'Git.Git'; Source = 'winget'; Ensure = 'Present'; Label = 'git present' },
        @{ Id = 'Spotify.Spotify'; Source = 'winget'; Ensure = 'Absent'; Label = 'spotify absent' },
        @{ Id = 'Contoso.SourceMove'; Source = 'msstore'; Ensure = 'Present'; Label = 'source move present' },
        @{ Id = 'Contoso.SourceMove'; Source = 'winget'; Ensure = 'Absent'; Label = 'source move old source absent' }
    )
    foreach ($check in $checks)
    {
        try
        {
            Assert-DscPackage -Yaml $generated -Id $check.Id -Source $check.Source -Ensure $check.Ensure -Label $check.Label
        } catch
        {
            $excerpt = if ($runText.Length -gt 4000) { $runText.Substring(0, 4000) } else { $runText }
            throw ("{0}`n{1}" -f $_.Exception.Message, $excerpt)
        }
    }
}
finally
{
    foreach ($name in $savedGitEnv.Keys)
    {
        Set-Item -LiteralPath "Env:$name" -Value $savedGitEnv[$name]
    }
    if (Test-Path -LiteralPath $fixtureRoot)
    {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $outputPath -Force -ErrorAction SilentlyContinue
}

if ($null -ne $dscBefore)
{
    $dscAfter = [System.IO.File]::ReadAllBytes($dscPath)
    $sameDsc = [System.Linq.Enumerable]::SequenceEqual($dscBefore, $dscAfter)
    if (-not $sameDsc)
    {
        throw 'generator test overwrote configuration.dsc.yaml'
    }
}
$packagesAfter = [System.IO.File]::ReadAllBytes($packagesFile)
$samePackages = [System.Linq.Enumerable]::SequenceEqual($packagesBefore, $packagesAfter)
if (-not $samePackages)
{
    throw 'generator test overwrote winget-packages.yml'
}

Write-Output 'PackageLine tests passed'
