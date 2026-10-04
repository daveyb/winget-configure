# PowerShell 7 profile, Terminal-Icons, Departure Mono, and Windows Terminal.
#
# winget configure can run this file under Windows PowerShell 5.1. $PROFILE
# and Install-Module in that host are not the PowerShell 7 paths, so a 5.1
# host relaunches this file with pwsh. Terminal-Icons is installed into the
# PowerShell 7 CurrentUser module path for the same reason.
#
# Fonts are registered for the current user. An elevated DSC securityContext
# makes every WinGetPackage fail with "The file name is too long."
#
# profiles.defaults.font does not replace a font set on a profile. Those
# per-profile font keys are removed so the default face applies to every
# profile. defaultProfile is the profile a new tab opens. List order is the
# dropdown order. PowerShell has to be first in both.

$ErrorActionPreference = 'Stop'

# winget configure runs this text as a script block under StrictMode.
# ScriptInfo has no Path property, so that member is read only when it exists.
# An empty path stays in this process. PowerShell 7 is that host.
$script:ShellProfileFile = $null
$commandInfo = $MyInvocation.MyCommand
if ($null -ne $commandInfo)
{
    $pathProperty = $commandInfo.PSObject.Properties['Path']
    if ($null -ne $pathProperty -and -not [string]::IsNullOrWhiteSpace([string]$pathProperty.Value))
    {
        $script:ShellProfileFile = [string]$pathProperty.Value
    }
}
if ([string]::IsNullOrWhiteSpace($script:ShellProfileFile))
{
    $script:ShellProfileFile = $PSCommandPath
}

if (($PSVersionTable.PSVersion.Major -lt 7) -and
    ($MyInvocation.InvocationName -ne '.') -and
    -not [string]::IsNullOrWhiteSpace($script:ShellProfileFile))
{
    $pwshCmd = Get-Command -Name pwsh -ErrorAction Stop
    $output = & $pwshCmd.Source -NoProfile -NonInteractive -File $script:ShellProfileFile
    $code = $LASTEXITCODE
    if ($code -ne 0)
    {
        exit $code
    }

    if ($null -eq $output)
    {
        return
    }

    $lines = @($output | Where-Object { $null -ne $_ -and "$_" -ne '' })
    if ($lines.Count -eq 0)
    {
        return
    }
    if ($lines.Count -eq 1 -and "$($lines[0])" -eq 'True')
    {
        return $true
    }
    if ($lines.Count -eq 1 -and "$($lines[0])" -eq 'False')
    {
        return $false
    }

    return $lines
}

$script:DefaultFontFace = 'DepartureMono Nerd Font'
$script:FontZipUri = 'https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/DepartureMono.zip'
$script:PowerShellProfileGuid = '{574e775e-4f2a-5b96-ac1e-a2962a402336}'
$script:PowerShellProfileSource = 'Windows.Terminal.PowershellCore'
$script:DepartureMonoFonts = @(
    @{ File = 'DepartureMonoNerdFont-Regular.otf'; Family = 'DepartureMono Nerd Font' }
    @{ File = 'DepartureMonoNerdFontMono-Regular.otf'; Family = 'DepartureMono Nerd Font Mono' }
    @{ File = 'DepartureMonoNerdFontPropo-Regular.otf'; Family = 'DepartureMono Nerd Font Propo' }
)

function Get-ShellProfileText
{
    [CmdletBinding()]
    param()

    $lines = @(
        'oh-my-posh --init --shell pwsh --config https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/refs/heads/main/themes/marcduiker.omp.json | Invoke-Expression'
        ''
        '# Install-Module -Name Terminal-Icons -Repository PSGallery'
        'Import-Module -Name Terminal-Icons'
    )
    return (($lines -join "`n") + "`n")
}

function ConvertTo-NormalizedProfileText
{
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Text)

    if ([string]::IsNullOrEmpty($Text))
    {
        return "`n"
    }

    $normalized = $Text -replace "`r`n", "`n" -replace "`r", "`n"
    return ($normalized.TrimEnd("`n") + "`n")
}

function Get-UserFontRegistryValueName
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Family,
        [Parameter(Mandatory)][string]$FileName
    )

    $extension = [System.IO.Path]::GetExtension($FileName).ToLowerInvariant()
    $kind = if ($extension -eq '.otf') { 'OpenType' } else { 'TrueType' }
    return ('{0} ({1})' -f $Family, $kind)
}

function Test-IsWindowsPowerShellProfile
{
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Name,
        [AllowEmptyString()][string]$CommandLine
    )

    if ($Name -eq 'Windows PowerShell')
    {
        return $true
    }
    if ($CommandLine -match '(?i)WindowsPowerShell\\v1\.0\\powershell\.exe')
    {
        return $true
    }

    return $false
}

function Get-PowerShellProfileRank
{
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Name,
        [AllowEmptyString()][string]$CommandLine,
        [AllowEmptyString()][string]$Source
    )

    if (Test-IsWindowsPowerShellProfile -Name $Name -CommandLine $CommandLine)
    {
        return -1
    }

    $commandIsPwsh = $CommandLine -match '(?i)(^|[\\/\s])pwsh\.exe(\s|$)'
    $sourceIsCore = $Source -eq $script:PowerShellProfileSource
    $nameIsPowerShell = $Name -eq 'PowerShell'
    if (-not ($nameIsPowerShell -or $sourceIsCore -or $commandIsPwsh))
    {
        return -1
    }
    if ($nameIsPowerShell -and $sourceIsCore)
    {
        return 0
    }
    if ($nameIsPowerShell)
    {
        return 1
    }
    if ($sourceIsCore)
    {
        return 2
    }

    return 3
}

function Get-JsonObjectString
{
    [CmdletBinding()]
    param(
        $Object,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $Object)
    {
        return ''
    }

    $jsonObject = $Object.AsObject()
    if (-not $jsonObject.ContainsKey($Name))
    {
        return ''
    }

    $value = $jsonObject[$Name]
    if ($null -eq $value)
    {
        return ''
    }

    return $value.ToString()
}

function Remove-JsonObjectKey
{
    [CmdletBinding()]
    param(
        $Object,
        [Parameter(Mandatory)][string]$Name
    )

    $jsonObject = $Object.AsObject()
    if ($jsonObject.ContainsKey($Name))
    {
        [void]$jsonObject.Remove($Name)
    }
}

function Convert-TerminalSettingsJson
{
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Json)

    $documentOptions = [System.Text.Json.JsonDocumentOptions]::new()
    $documentOptions.CommentHandling = [System.Text.Json.JsonCommentHandling]::Skip
    $documentOptions.AllowTrailingCommas = $true
    $nodeOptions = [System.Text.Json.Nodes.JsonNodeOptions]::new()
    $root = [System.Text.Json.Nodes.JsonNode]::Parse($Json, $nodeOptions, $documentOptions)
    if ($null -eq $root -or $root.GetType().Name -ne 'JsonObject')
    {
        throw 'Windows Terminal settings must be a JSON object.'
    }

    $rootObject = $root.AsObject()
    if (-not $rootObject.ContainsKey('profiles') -or $null -eq $rootObject['profiles'])
    {
        $rootObject['profiles'] = [System.Text.Json.Nodes.JsonObject]::new()
    }

    $profiles = $rootObject['profiles'].AsObject()
    if (-not $profiles.ContainsKey('defaults') -or $null -eq $profiles['defaults'])
    {
        $profiles['defaults'] = [System.Text.Json.Nodes.JsonObject]::new()
    }

    $defaults = $profiles['defaults'].AsObject()
    Remove-JsonObjectKey -Object $defaults -Name 'fontFace'
    if (-not $defaults.ContainsKey('font') -or $null -eq $defaults['font'] -or $defaults['font'].GetType().Name -ne 'JsonObject')
    {
        $defaults['font'] = [System.Text.Json.Nodes.JsonObject]::new()
    }
    $defaults['font'].AsObject()['face'] = $script:DefaultFontFace

    if (-not $profiles.ContainsKey('list') -or $null -eq $profiles['list'] -or $profiles['list'].GetType().Name -ne 'JsonArray')
    {
        $profiles['list'] = [System.Text.Json.Nodes.JsonArray]::new()
    }

    $list = $profiles['list'].AsArray()
    $bestIndex = -1
    $bestRank = 99
    for ($index = 0; $index -lt $list.Count; $index++)
    {
        $name = Get-JsonObjectString -Object $list[$index] -Name 'name'
        $commandLine = Get-JsonObjectString -Object $list[$index] -Name 'commandline'
        $source = Get-JsonObjectString -Object $list[$index] -Name 'source'
        $rank = Get-PowerShellProfileRank -Name $name -CommandLine $commandLine -Source $source
        if ($rank -ge 0 -and $rank -lt $bestRank)
        {
            $bestRank = $rank
            $bestIndex = $index
        }
    }

    if ($bestIndex -lt 0)
    {
        $created = [System.Text.Json.Nodes.JsonObject]::new()
        $created['guid'] = $script:PowerShellProfileGuid
        $created['hidden'] = [System.Text.Json.Nodes.JsonValue]::Create($false)
        $created['name'] = 'PowerShell'
        $created['source'] = $script:PowerShellProfileSource
        $list.Insert(0, $created)
        $chosen = $created
    }
    else
    {
        $chosen = $list[$bestIndex]
        if ($bestIndex -ne 0)
        {
            $list.RemoveAt($bestIndex)
            $list.Insert(0, $chosen)
        }
    }

    $chosenObject = $chosen.AsObject()
    $guid = Get-JsonObjectString -Object $chosenObject -Name 'guid'
    if ([string]::IsNullOrWhiteSpace($guid))
    {
        $guid = $script:PowerShellProfileGuid
        $chosenObject['guid'] = $guid
    }
    $chosenObject['hidden'] = [System.Text.Json.Nodes.JsonValue]::Create($false)
    $rootObject['defaultProfile'] = $guid

    foreach ($item in @($list))
    {
        Remove-JsonObjectKey -Object $item -Name 'font'
        Remove-JsonObjectKey -Object $item -Name 'fontFace'
    }

    $serializerOptions = [System.Text.Json.JsonSerializerOptions]::new()
    $serializerOptions.WriteIndented = $true
    $indentSize = $serializerOptions.PSObject.Properties['IndentSize']
    if ($null -ne $indentSize)
    {
        $serializerOptions.IndentSize = 4
    }

    $encoderType = 'System.Text.Encodings.Web.JavaScriptEncoder' -as [type]
    if ($null -ne $encoderType)
    {
        $serializerOptions.Encoder = $encoderType::UnsafeRelaxedJsonEscaping
    }

    $text = $root.ToJsonString($serializerOptions)
    $text = $text.Replace("`n", "`r`n").Replace("`r`r`n", "`r`n")
    if (-not $text.EndsWith("`r`n"))
    {
        $text += "`r`n"
    }

    return $text
}

function Test-TerminalSettingsText
{
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Json)

    if ([string]::IsNullOrWhiteSpace($Json))
    {
        return $false
    }

    try
    {
        $updated = Convert-TerminalSettingsJson -Json $Json
        $currentFacts = Get-TerminalSettingsFacts -Json $Json
        $updatedFacts = Get-TerminalSettingsFacts -Json $updated
        return ($currentFacts -eq $updatedFacts)
    }
    catch
    {
        return $false
    }
}

function Get-TerminalSettingsFacts
{
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Json)

    $documentOptions = [System.Text.Json.JsonDocumentOptions]::new()
    $documentOptions.CommentHandling = [System.Text.Json.JsonCommentHandling]::Skip
    $documentOptions.AllowTrailingCommas = $true
    $nodeOptions = [System.Text.Json.Nodes.JsonNodeOptions]::new()
    $root = [System.Text.Json.Nodes.JsonNode]::Parse($Json, $nodeOptions, $documentOptions).AsObject()
    $profiles = $root['profiles'].AsObject()
    $defaults = $profiles['defaults'].AsObject()
    $face = ''
    if ($defaults.ContainsKey('font') -and $null -ne $defaults['font'])
    {
        $face = Get-JsonObjectString -Object $defaults['font'] -Name 'face'
    }

    $list = $profiles['list'].AsArray()
    $firstName = ''
    $firstGuid = ''
    $firstSource = ''
    $firstCommand = ''
    $firstHidden = ''
    $profileFontCount = 0
    if ($list.Count -gt 0)
    {
        $firstName = Get-JsonObjectString -Object $list[0] -Name 'name'
        $firstGuid = Get-JsonObjectString -Object $list[0] -Name 'guid'
        $firstSource = Get-JsonObjectString -Object $list[0] -Name 'source'
        $firstCommand = Get-JsonObjectString -Object $list[0] -Name 'commandline'
        $firstObject = $list[0].AsObject()
        if ($firstObject.ContainsKey('hidden'))
        {
            $firstHidden = $firstObject['hidden'].ToString().ToLowerInvariant()
        }
        foreach ($item in @($list))
        {
            $itemObject = $item.AsObject()
            if ($itemObject.ContainsKey('font') -or $itemObject.ContainsKey('fontFace'))
            {
                $profileFontCount++
            }
        }
    }

    $defaultProfile = Get-JsonObjectString -Object $root -Name 'defaultProfile'
    $defaultFontFace = ''
    if ($defaults.ContainsKey('fontFace'))
    {
        $defaultFontFace = Get-JsonObjectString -Object $defaults -Name 'fontFace'
    }

    return ('face={0};defaultFontFace={1};first={2};guid={3};source={4};command={5};hidden={6};defaultProfile={7};profileFonts={8}' -f $face, $defaultFontFace, $firstName, $firstGuid, $firstSource, $firstCommand, $firstHidden, $defaultProfile, $profileFontCount)
}

function Get-PwshProfilePath
{
    [CmdletBinding()]
    param()

    $pwshCmd = Get-Command -Name pwsh -ErrorAction SilentlyContinue
    if ($pwshCmd)
    {
        $output = & $pwshCmd.Source -NoProfile -NonInteractive -Command '$PROFILE.CurrentUserCurrentHost'
        if ($LASTEXITCODE -eq 0 -and $output)
        {
            $path = @($output)[-1]
            if ($path)
            {
                return $path.ToString().Trim()
            }
        }
    }

    return (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Microsoft.PowerShell_profile.ps1')
}

function Test-PwshProfileContent
{
    [CmdletBinding()]
    param()

    $path = Get-PwshProfilePath
    if (-not (Test-Path -LiteralPath $path))
    {
        return $false
    }

    $current = [System.IO.File]::ReadAllText($path)
    $desired = Get-ShellProfileText
    return ((ConvertTo-NormalizedProfileText $current) -eq (ConvertTo-NormalizedProfileText $desired))
}

function Set-PwshProfileContent
{
    [CmdletBinding()]
    param()

    $path = Get-PwshProfilePath
    $desired = Get-ShellProfileText
    if (Test-PwshProfileContent)
    {
        return
    }

    $directory = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $directory))
    {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $encoding = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($path, $desired, $encoding)
}

function Test-TerminalIconsInstalled
{
    [CmdletBinding()]
    param()

    $pwshCmd = Get-Command -Name pwsh -ErrorAction SilentlyContinue
    if (-not $pwshCmd)
    {
        return $false
    }

    $output = & $pwshCmd.Source -NoProfile -NonInteractive -Command "if (Get-Module -ListAvailable -Name Terminal-Icons) { 'present' } else { 'missing' }"
    if ($LASTEXITCODE -ne 0)
    {
        return $false
    }

    return ((@($output) -join "`n") -match '(?m)^present$')
}

function Install-TerminalIconsModule
{
    [CmdletBinding()]
    param()

    if (Test-TerminalIconsInstalled)
    {
        return
    }

    $pwshCmd = Get-Command -Name pwsh -ErrorAction SilentlyContinue
    if (-not $pwshCmd)
    {
        throw 'pwsh is not on PATH. Install Microsoft.PowerShell and run this again.'
    }

    $runner = Join-Path ([System.IO.Path]::GetTempPath()) ('Install-TerminalIcons-' + [guid]::NewGuid().ToString('n') + '.ps1')
    $code = @'
$ErrorActionPreference = "Stop"
$ConfirmPreference = "None"
if (Get-Module -ListAvailable -Name Terminal-Icons) { return }
$nuget = @(Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction SilentlyContinue | Where-Object { $_.Version -ge [version]"2.8.5.201" })
if ($nuget.Count -eq 0) {
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null
}
$repo = Get-PSRepository -Name PSGallery -ErrorAction Stop
if ($repo.InstallationPolicy -ne "Trusted") {
    Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
}
Install-Module -Name Terminal-Icons -Repository PSGallery -Scope CurrentUser -Force -AllowClobber
if (-not (Get-Module -ListAvailable -Name Terminal-Icons)) {
    throw "Terminal-Icons is not installed"
}
'@
    $encoding = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($runner, $code, $encoding)
    try
    {
        & $pwshCmd.Source -NoProfile -NonInteractive -File $runner
        if ($LASTEXITCODE -ne 0)
        {
            throw "Install-Module Terminal-Icons failed with exit $LASTEXITCODE"
        }
    }
    finally
    {
        Remove-Item -LiteralPath $runner -Force -ErrorAction SilentlyContinue
    }
}

function Get-UserFontDirectory
{
    [CmdletBinding()]
    param()

    return (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts')
}

function Test-DepartureMonoFontsInstalled
{
    [CmdletBinding()]
    param()

    $directory = Get-UserFontDirectory
    $registryPath = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    foreach ($font in $script:DepartureMonoFonts)
    {
        $destination = Join-Path $directory $font.File
        if (-not (Test-Path -LiteralPath $destination))
        {
            return $false
        }

        $registryName = Get-UserFontRegistryValueName -Family $font.Family -FileName $font.File
        $current = $null
        if (Test-Path -LiteralPath $registryPath)
        {
            $property = Get-ItemProperty -LiteralPath $registryPath -Name $registryName -ErrorAction SilentlyContinue
            if ($property)
            {
                $current = $property.$registryName
            }
        }
        if ($current -ne $destination)
        {
            return $false
        }
    }

    return $true
}

function Install-UserFontFile
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SourcePath,
        [Parameter(Mandatory)][string]$Family
    )

    $directory = Get-UserFontDirectory
    if (-not (Test-Path -LiteralPath $directory))
    {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $fileName = [System.IO.Path]::GetFileName($SourcePath)
    $destination = Join-Path $directory $fileName
    $copy = $true
    if (Test-Path -LiteralPath $destination)
    {
        $sourceHash = (Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash
        $destinationHash = (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash
        if ($sourceHash -eq $destinationHash)
        {
            $copy = $false
        }
    }
    if ($copy)
    {
        Copy-Item -LiteralPath $SourcePath -Destination $destination -Force
    }

    $registryPath = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    if (-not (Test-Path -LiteralPath $registryPath))
    {
        New-Item -Path $registryPath -Force | Out-Null
    }

    $registryName = Get-UserFontRegistryValueName -Family $Family -FileName $fileName
    $current = $null
    $property = Get-ItemProperty -LiteralPath $registryPath -Name $registryName -ErrorAction SilentlyContinue
    if ($property)
    {
        $current = $property.$registryName
    }
    if ($current -ne $destination)
    {
        New-ItemProperty -LiteralPath $registryPath -Name $registryName -Value $destination -PropertyType String -Force | Out-Null
    }

    return $destination
}

function Add-UserFontResource
{
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Paths)

    if (-not ('Win32FontChange.Native' -as [type]))
    {
        Add-Type -Namespace Win32FontChange -Name Native -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("gdi32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern int AddFontResource(string lpFileName);
[System.Runtime.InteropServices.DllImport("user32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern System.IntPtr SendMessage(System.IntPtr hWnd, uint Msg, System.IntPtr wParam, System.IntPtr lParam);
'@
    }

    foreach ($path in $Paths)
    {
        [void][Win32FontChange.Native]::AddFontResource($path)
    }

    $broadcast = [IntPtr]0xffff
    [void][Win32FontChange.Native]::SendMessage($broadcast, [uint32]0x001D, [IntPtr]::Zero, [IntPtr]::Zero)
}

function Install-DepartureMonoFonts
{
    [CmdletBinding()]
    param()

    if (Test-DepartureMonoFontsInstalled)
    {
        return
    }

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('DepartureMono-' + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    $previousProgress = $ProgressPreference
    try
    {
        $ProgressPreference = 'SilentlyContinue'
        $zip = Join-Path $tempRoot 'DepartureMono.zip'
        Invoke-WebRequest -Uri $script:FontZipUri -OutFile $zip -UseBasicParsing
        $extract = Join-Path $tempRoot 'extract'
        Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
        $installed = New-Object System.Collections.Generic.List[string]
        foreach ($font in $script:DepartureMonoFonts)
        {
            $source = Join-Path $extract $font.File
            if (-not (Test-Path -LiteralPath $source))
            {
                throw "Departure Mono archive is missing $($font.File)"
            }

            $installed.Add((Install-UserFontFile -SourcePath $source -Family $font.Family))
        }

        Add-UserFontResource -Paths $installed.ToArray()
    }
    finally
    {
        $ProgressPreference = $previousProgress
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (-not (Test-DepartureMonoFontsInstalled))
    {
        throw 'Departure Mono fonts are not registered for the current user.'
    }
}

function Get-ExistingWindowsTerminalSettingsPaths
{
    [CmdletBinding()]
    param()

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json')
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json')
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    )
    $found = New-Object System.Collections.Generic.List[string]
    foreach ($candidate in $candidates)
    {
        if (Test-Path -LiteralPath $candidate)
        {
            $found.Add($candidate)
        }
    }

    return $found.ToArray()
}

function Get-WindowsTerminalSettingsWritePaths
{
    [CmdletBinding()]
    param()

    $existing = @(Get-ExistingWindowsTerminalSettingsPaths)
    if ($existing.Count -gt 0)
    {
        return $existing
    }

    $packageRoot = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe'
    if (Test-Path -LiteralPath $packageRoot)
    {
        return @((Join-Path $packageRoot 'LocalState\settings.json'))
    }

    return @((Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json'))
}

function Get-EmptyTerminalSettingsJson
{
    [CmdletBinding()]
    param()

    return @'
{
  "$schema": "https://aka.ms/terminal-profiles-schema",
  "profiles": {
    "defaults": {},
    "list": []
  }
}
'@
}

function Test-WindowsTerminalSettings
{
    [CmdletBinding()]
    param()

    $paths = @(Get-ExistingWindowsTerminalSettingsPaths)
    if ($paths.Count -eq 0)
    {
        return $false
    }

    foreach ($path in $paths)
    {
        $json = [System.IO.File]::ReadAllText($path)
        if (-not (Test-TerminalSettingsText -Json $json))
        {
            return $false
        }
    }

    return $true
}

function Set-WindowsTerminalSettings
{
    [CmdletBinding()]
    param()

    $encoding = New-Object System.Text.UTF8Encoding $false
    foreach ($path in @(Get-WindowsTerminalSettingsWritePaths))
    {
        $json = Get-EmptyTerminalSettingsJson
        if (Test-Path -LiteralPath $path)
        {
            $json = [System.IO.File]::ReadAllText($path)
        }
        if (Test-TerminalSettingsText -Json $json)
        {
            continue
        }

        $updated = Convert-TerminalSettingsJson -Json $json
        $directory = Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $directory))
        {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }

        [System.IO.File]::WriteAllText($path, $updated, $encoding)
    }

    if (-not (Test-WindowsTerminalSettings))
    {
        throw 'Windows Terminal settings do not have Departure Mono and PowerShell first.'
    }
}

function Get-ShellProfileFacts
{
    [CmdletBinding()]
    param()

    return @{
        Profile  = [bool](Test-PwshProfileContent)
        Icons    = [bool](Test-TerminalIconsInstalled)
        Fonts    = [bool](Test-DepartureMonoFontsInstalled)
        Terminal = [bool](Test-WindowsTerminalSettings)
    }
}

function Format-ShellProfileFacts
{
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Facts)

    $profileState = if ($Facts.Profile) { 'match' } else { 'missing' }
    $iconsState = if ($Facts.Icons) { 'present' } else { 'missing' }
    $fontsState = if ($Facts.Fonts) { 'installed' } else { 'missing' }
    $terminalState = if ($Facts.Terminal) { 'ready' } else { 'missing' }
    return ('profile={0};icons={1};fonts={2};terminal={3}' -f $profileState, $iconsState, $fontsState, $terminalState)
}

function Get-ShellProfileReport
{
    [CmdletBinding()]
    param()

    if ($PSVersionTable.PSVersion.Major -lt 7)
    {
        $result = Invoke-ShellProfileOnPwsh -Command 'Get'
        return @{ Result = $result }
    }

    return @{ Result = (Format-ShellProfileFacts -Facts (Get-ShellProfileFacts)) }
}

function Test-ShellProfile
{
    [CmdletBinding()]
    param()

    if ($PSVersionTable.PSVersion.Major -lt 7)
    {
        $code = Invoke-ShellProfileOnPwsh -Command 'Test'
        if ($code -eq 0)
        {
            return $true
        }
        if ($code -eq 1)
        {
            return $false
        }

        throw "Test-ShellProfile failed in pwsh with exit $code"
    }

    try
    {
        $facts = Get-ShellProfileFacts
        return ($facts.Profile -and $facts.Icons -and $facts.Fonts -and $facts.Terminal)
    }
    catch
    {
        return $false
    }
}

function Set-ShellProfile
{
    [CmdletBinding()]
    param()

    if ($PSVersionTable.PSVersion.Major -lt 7)
    {
        $code = Invoke-ShellProfileOnPwsh -Command 'Set'
        if ($code -ne 0)
        {
            throw "Set-ShellProfile failed in pwsh with exit $code"
        }

        return
    }

    $errors = New-Object System.Collections.Generic.List[string]
    foreach ($step in @(
            { Set-PwshProfileContent }
            { Install-TerminalIconsModule }
            { Install-DepartureMonoFonts }
            { Set-WindowsTerminalSettings }
        ))
    {
        try
        {
            & $step
        }
        catch
        {
            $errors.Add($_.Exception.Message)
        }
    }

    if ($errors.Count -gt 0)
    {
        throw ($errors -join ' ')
    }
}

function Invoke-ShellProfileOnPwsh
{
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Command)

    $pwshCmd = Get-Command -Name pwsh -ErrorAction Stop
    $path = $script:ShellProfileFile
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path))
    {
        throw 'Shell profile script path is not available to relaunch under pwsh.'
    }

    $previous = [Environment]::GetEnvironmentVariable('SHELL_PROFILE_COMMAND')
    try
    {
        [Environment]::SetEnvironmentVariable('SHELL_PROFILE_COMMAND', $Command)
        $output = & $pwshCmd.Source -NoProfile -NonInteractive -File $path
        $code = $LASTEXITCODE
    }
    finally
    {
        [Environment]::SetEnvironmentVariable('SHELL_PROFILE_COMMAND', $previous)
    }

    if ($Command -eq 'Get')
    {
        if ($code -ne 0)
        {
            throw "Get-ShellProfileReport failed in pwsh with exit $code"
        }

        return ((@($output) | Select-Object -Last 1).ToString())
    }

    return $code
}

$shellCommand = [Environment]::GetEnvironmentVariable('SHELL_PROFILE_COMMAND')
if (($MyInvocation.InvocationName -ne '.') -and $shellCommand)
{
    [Environment]::SetEnvironmentVariable('SHELL_PROFILE_COMMAND', $null)
    if ($shellCommand -eq 'Test')
    {
        if (Test-ShellProfile) { exit 0 } else { exit 1 }
    }
    if ($shellCommand -eq 'Set')
    {
        Set-ShellProfile
        exit 0
    }
    if ($shellCommand -eq 'Get')
    {
        $report = Get-ShellProfileReport
        Write-Output $report.Result
        exit 0
    }
    if ($shellCommand -eq 'Text')
    {
        $textPath = [Environment]::GetEnvironmentVariable('SHELL_PROFILE_OUT')
        if ([string]::IsNullOrWhiteSpace($textPath))
        {
            throw 'SHELL_PROFILE_OUT is required for the Text command.'
        }

        $encoding = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($textPath, (Get-ShellProfileText), $encoding)
        exit 0
    }

    Write-Error "Unknown shell profile command: $shellCommand"
    exit 2
}
