#Requires -Version 7
$ErrorActionPreference = 'Stop'

$helper = Join-Path $PSScriptRoot 'ShellProfile.ps1'
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

$expectedProfile = "oh-my-posh --init --shell pwsh --config https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/refs/heads/main/themes/marcduiker.omp.json | Invoke-Expression`n`n# Install-Module -Name Terminal-Icons -Repository PSGallery`nImport-Module -Name Terminal-Icons`n"
Assert-Equal (Get-ShellProfileText) $expectedProfile 'profile text'
Assert-Equal (ConvertTo-NormalizedProfileText ($expectedProfile -replace "`n", "`r`n")) $expectedProfile 'profile newline normalization'
Assert-Equal (Get-UserFontRegistryValueName -Family 'DepartureMono Nerd Font' -FileName 'DepartureMonoNerdFont-Regular.otf') 'DepartureMono Nerd Font (OpenType)' 'otf registry name'
Assert-Equal (Get-PowerShellProfileRank -Name 'Windows PowerShell' -CommandLine '%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe' -Source '') -1 'windows powershell rank'
Assert-Equal (Get-PowerShellProfileRank -Name 'PowerShell' -CommandLine '' -Source 'Windows.Terminal.PowershellCore') 0 'powershell rank'

$fixture = @'
{
  "$schema": "https://aka.ms/terminal-profiles-schema",
  "copyOnSelect": false,
  "defaultProfile": "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}",
  "profiles": {
    "defaults": {
      "fontFace": "Cascadia Mono"
    },
    "list": [
      {
        "commandline": "%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe",
        "font": { "face": "Consolas" },
        "guid": "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}",
        "name": "Windows PowerShell"
      },
      {
        "fontFace": "Courier New",
        "guid": "{0caa0dad-35be-5f56-a8ff-afceeeaa6101}",
        "name": "Command Prompt"
      },
      {
        "guid": "{574e775e-4f2a-5b96-ac1e-a2962a402336}",
        "hidden": true,
        "name": "PowerShell",
        "source": "Windows.Terminal.PowershellCore"
      }
    ]
  },
  "schemes": [
    { "name": "Campbell", "background": "#0C0C0C" }
  ]
}
'@

Assert-True (-not (Test-TerminalSettingsText -Json $fixture)) 'fixture starts non-compliant'
$updated = Convert-TerminalSettingsJson -Json $fixture
$again = Convert-TerminalSettingsJson -Json $updated
Assert-Equal $again $updated 'second update is byte-identical'
Assert-True (Test-TerminalSettingsText -Json $updated) 'updated settings are compliant'

$parsed = $updated | ConvertFrom-Json
Assert-Equal $parsed.'$schema' 'https://aka.ms/terminal-profiles-schema' 'schema survives'
Assert-Equal $parsed.copyOnSelect $false 'unrelated setting survives'
Assert-Equal $parsed.profiles.defaults.font.face 'DepartureMono Nerd Font' 'default face'
Assert-True ($null -eq $parsed.profiles.defaults.PSObject.Properties['fontFace']) 'legacy default fontFace removed'
Assert-Equal $parsed.profiles.list[0].name 'PowerShell' 'powershell is first'
Assert-Equal $parsed.profiles.list[0].guid '{574e775e-4f2a-5b96-ac1e-a2962a402336}' 'powershell guid'
Assert-Equal $parsed.profiles.list[0].hidden $false 'powershell is visible'
Assert-Equal $parsed.defaultProfile $parsed.profiles.list[0].guid 'defaultProfile opens powershell'
Assert-Equal $parsed.profiles.list[1].name 'Windows PowerShell' 'windows powershell follows'
Assert-True ($null -eq $parsed.profiles.list[1].PSObject.Properties['font']) 'profile font override removed'
Assert-True ($null -eq $parsed.profiles.list[2].PSObject.Properties['fontFace']) 'profile fontFace removed'
Assert-Equal $parsed.profiles.list[2].name 'Command Prompt' 'command prompt stays'
Assert-Equal $parsed.schemes[0].name 'Campbell' 'scheme survives'
Assert-Equal $parsed.schemes[0].background '#0C0C0C' 'scheme color is not escaped'

$inserted = Convert-TerminalSettingsJson -Json @'
{
  "profiles": {
    "defaults": {},
    "list": [
      {
        "guid": "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}",
        "name": "Windows PowerShell",
        "commandline": "%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"
      }
    ]
  }
}
'@
$insertedParsed = $inserted | ConvertFrom-Json
Assert-Equal $insertedParsed.profiles.list[0].name 'PowerShell' 'missing powershell is inserted first'
Assert-Equal $insertedParsed.profiles.list[0].source 'Windows.Terminal.PowershellCore' 'inserted source'
Assert-Equal $insertedParsed.profiles.list[0].guid '{574e775e-4f2a-5b96-ac1e-a2962a402336}' 'inserted guid'
Assert-Equal $insertedParsed.profiles.list[1].name 'Windows PowerShell' 'existing windows powershell remains'
Assert-Equal $insertedParsed.defaultProfile '{574e775e-4f2a-5b96-ac1e-a2962a402336}' 'inserted profile is the default'

$preview = Convert-TerminalSettingsJson -Json @'
{
  "profiles": {
    "defaults": {},
    "list": [
      {
        "guid": "{aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa}",
        "name": "PowerShell Preview",
        "source": "Windows.Terminal.PowershellCore"
      },
      {
        "commandline": "C:\\Program Files\\PowerShell\\7\\pwsh.exe",
        "guid": "{bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb}",
        "name": "PowerShell"
      }
    ]
  }
}
'@
$previewParsed = $preview | ConvertFrom-Json
Assert-Equal $previewParsed.profiles.list[0].guid '{bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb}' 'exact PowerShell name beats preview'
Assert-Equal $previewParsed.defaultProfile '{bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb}' 'default follows the named profile'

$commented = @'
{
  // keep the shell order
  "profiles": {
    "defaults": {},
    "list": [
      { "name": "Windows PowerShell", "guid": "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}", "commandline": "%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" },
      { "name": "PowerShell", "guid": "{574e775e-4f2a-5b96-ac1e-a2962a402336}", "source": "Windows.Terminal.PowershellCore" },
    ]
  }
}
'@
$commentedParsed = (Convert-TerminalSettingsJson -Json $commented) | ConvertFrom-Json
Assert-Equal $commentedParsed.profiles.list[0].name 'PowerShell' 'jsonc comment and trailing comma parse'

$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
Assert-True (Test-Path -LiteralPath $windowsPowerShell) 'Windows PowerShell is present'
$previousCommand = [Environment]::GetEnvironmentVariable('SHELL_PROFILE_COMMAND')
$previousOut = [Environment]::GetEnvironmentVariable('SHELL_PROFILE_OUT')
$textPath = Join-Path ([System.IO.Path]::GetTempPath()) ('shell-profile-text-' + [guid]::NewGuid().ToString('n') + '.txt')
try
{
    [Environment]::SetEnvironmentVariable('SHELL_PROFILE_COMMAND', 'Text')
    [Environment]::SetEnvironmentVariable('SHELL_PROFILE_OUT', $textPath)
    & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $helper | Out-Null
    if ($LASTEXITCODE -ne 0)
    {
        throw "Windows PowerShell relaunch exited $LASTEXITCODE"
    }
}
finally
{
    [Environment]::SetEnvironmentVariable('SHELL_PROFILE_COMMAND', $previousCommand)
    [Environment]::SetEnvironmentVariable('SHELL_PROFILE_OUT', $previousOut)
}
Assert-True (Test-Path -LiteralPath $textPath) 'Windows PowerShell relaunch wrote the profile text'
$windowsText = [System.IO.File]::ReadAllText($textPath)
Remove-Item -LiteralPath $textPath -Force
Assert-Equal $windowsText $expectedProfile 'Windows PowerShell 5.1 relaunches the helper'

Set-StrictMode -Version Latest
$helperText = [System.IO.File]::ReadAllText($helper)
$previousDscCommand = [Environment]::GetEnvironmentVariable('SHELL_PROFILE_COMMAND')
[Environment]::SetEnvironmentVariable('SHELL_PROFILE_COMMAND', $null)
try
{
    $dscGet = [scriptblock]::Create($helperText + "`nreturn (Get-ShellProfileReport)`n")
    $dscReport = & $dscGet
    $dscTest = [scriptblock]::Create($helperText + "`nreturn (Test-ShellProfile)`n")
    $dscResult = & $dscTest
}
finally
{
    [Environment]::SetEnvironmentVariable('SHELL_PROFILE_COMMAND', $previousDscCommand)
}
Assert-True ($null -ne $dscReport -and $dscReport.Result -match '^profile=') 'strict scriptblock get returns facts'
Assert-True ($dscResult -is [bool]) 'strict scriptblock test returns a boolean'

Write-Output 'ShellProfile tests passed'
