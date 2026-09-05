#Requires -Version 5.1
<#
.SYNOPSIS
    Generates a single winget-configure DSC YAML file from winget-packages.yml,
    tracking removals and pruning stale 'Absent' entries.

.DESCRIPTION
    This script reads the current `winget-packages.yml` and compares it against
    a previous version of that SAME file in Git (configurable via -CompareRef, defaulting to HEAD).

    It then generates a `.configurations/configuration.dsc.yaml` file that reflects
    the desired state:

    - Packages present in the current YAML are emitted with `ensure: Present`.
    - Packages removed from the current YAML, but present in the previous (HEAD)
      YAML, are kept as resources but emitted with `ensure: Absent`.
    - If a package resource is already `ensure: Absent` in the existing DSC output,
      AND that package is not present in the previous (HEAD) YAML, then the resource
      is removed entirely from the generated DSC output.

    This provides a clean lifecycle:
      Present (in YAML) -> Absent tombstone (first commit after removal) -> pruned (next commit)

.PARAMETER PackagesFile
    Path to the source YAML file. Defaults to `winget-packages.yml` next to this script.

.PARAMETER OutputFile
    Path to write the generated DSC YAML file. Defaults to `.configurations\configuration.dsc.yaml`
    next to this script.

.PARAMETER Force
    Overwrites the output file without prompting if it already exists.

.PARAMETER CompareRef
    The Git reference (e.g., HEAD, HEAD~1) to compare against. Defaults to 'HEAD'.

.PARAMETER ChangesOutputFile
    Optional path to write machine-readable JSON output of changes (added, removed, pruned).

.EXAMPLE
    .\New-WingetConfiguration.ps1
    Generates `.configurations\configuration.dsc.yaml` from `winget-packages.yml`, comparing against Git HEAD.

.EXAMPLE
    .\New-WingetConfiguration.ps1 -Force
    Regenerates the output file without prompting.

.EXAMPLE
    .\New-WingetConfiguration.ps1 -Force -CompareRef HEAD~1 -ChangesOutputFile changes.json
    CI mode: compares against parent commit, writes machine-readable change data.

.NOTES
    - Git must be installed and available on PATH for removal tracking.
    - Comparison is case-sensitive (winget IDs are case-sensitive).
    - Use -CompareRef HEAD~1 in CI where HEAD is already the current commit.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$PackagesFile,
    [string]$OutputFile,
    [switch]$Force,
    [string]$CompareRef = 'HEAD',
    [string]$ChangesOutputFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Constants ─────────────────────────────────────────────────────────────────

$DSC_SCHEMA_COMMENT = '# yaml-language-server: $schema=https://aka.ms/configuration-dsc-schema/0.2'
$DSC_SCHEMA_VERSION = '0.2.0'

# ── Output helpers ────────────────────────────────────────────────────────────

function Write-Info
{ param([string]$m) Write-Host $m -ForegroundColor Blue
}
function Write-Success
{ param([string]$m) Write-Host $m -ForegroundColor Green
}
function Write-Warn
{ param([string]$m) Write-Warning $m
}

# ── Path helpers (PowerShell 5.1 compatible) ─────────────────────────────────

function Get-RelativePath
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [Parameter(Mandatory)][string]$TargetPath
    )

    $baseFull = (Resolve-Path -Path $BasePath).Path.TrimEnd('\') + '\'
    $targetFull = (Resolve-Path -Path $TargetPath).Path

    $baseUri = New-Object System.Uri($baseFull)
    $targetUri = New-Object System.Uri($targetFull)

    $relUri = $baseUri.MakeRelativeUri($targetUri)
    $rel = [System.Uri]::UnescapeDataString($relUri.ToString())

    # Git wants forward slashes, but we also use it for display
    return $rel.Replace('/', '\')
}

# ── Git helpers ───────────────────────────────────────────────────────────────

function Test-GitAvailable
{
    try
    {
        $null = & git --version 2>$null
        return ($LASTEXITCODE -eq 0)
    } catch
    {
        return $false
    }
}

function Get-GitRepoRoot
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$StartDirectory
    )

    try
    {
        $root = & git -C $StartDirectory rev-parse --show-toplevel 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($root))
        {
            return $root.Trim()
        }
    } catch
    {
    }

    return $null
}

function Get-GitFileContentAtRef
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepoRoot,
        [Parameter(Mandatory)][string]$RepoRelativePath,
        [Parameter(Mandatory)][string]$Ref # e.g., 'HEAD', 'HEAD~1'
    )

    # git show expects forward slashes
    $gitPath = $RepoRelativePath.Replace('\', '/')
    $spec = "${Ref}:${gitPath}"

    try
    {
        $content = & git -C $RepoRoot show $spec 2>$null
        if ($LASTEXITCODE -eq 0)
        {
            return $content
        }
    } catch
    {
        Write-Warning "Git command failed: $($_.Exception.Message)"
    }

    return $null
}

# ── YAML parsing (winget-packages.yml subset) ─────────────────────────────────

function Parse-PackagesYamlLines
{
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [string[]]$Lines = @()
    )

    # Defensive check: if Lines is null or empty, return empty array immediately
    if ($null -eq $Lines -or $Lines.Count -eq 0)
    {
        Write-Verbose "Parse-PackagesYamlLines received null or empty Lines array. Returning empty."
        return @()
    }

    $entries = New-Object System.Collections.Generic.List[hashtable]
    $currentCategory = 'Uncategorised'
    $inPackages = $false

    foreach ($rawLine in $Lines)
    {
        if ([string]::IsNullOrWhiteSpace($rawLine))
        { continue
        }

        # Decorative headers like: "# ── Development tools & languages ─────────"
        if ($rawLine -match '^\s*#\s*[^\w\s]+\s+(.+?)\s+[^\w\s]+\s*$')
        {
            $currentCategory = $Matches[1].Trim()
            continue
        }

        # Other comments
        if ($rawLine -match '^\s*#')
        { continue
        }

        if ($rawLine -match '^\s*packages\s*:\s*$')
        {
            $inPackages = $true
            continue
        }

        if (-not $inPackages)
        { continue
        }

        # Category keys like "  development:" (we ignore; category comes from decorative comment)
        if ($rawLine -match '^\s{2,}[\w-]+\s*:\s*$')
        { continue
        }

        # Package list items like "    - Git.Git # comment"
        if ($rawLine -match '^\s*-\s+([^\s#]+)(?:\s+#\s*(.*))?\s*$')
        {
            $id = $Matches[1].Trim()
            $comment = ''
            if ($Matches.Count -ge 3 -and $null -ne $Matches[2])
            {
                $comment = $Matches[2].Trim()
            }

            if (-not [string]::IsNullOrWhiteSpace($id))
            {
                $entries.Add(@{
                        Id       = $id
                        Category = $currentCategory
                        Comment  = $comment
                    })
            }
        }
    }

    return $entries
}

function Read-PackagesYaml
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    if (-not (Test-Path $Path))
    {
        throw "Packages file not found: $Path"
    }

    $lines = Get-Content -Path $Path -Encoding UTF8

    # Explicitly check for null or empty array from Get-Content
    if ($lines -eq $null -or $lines.Length -eq 0)
    {
        Write-Warning "Packages file '$Path' returned no content (null or empty array). No packages will be processed."
        return @()
    }

    # Check if all lines are whitespace (this is a secondary check)
    if ($lines -join '' -match '^\s*$')
    {
        Write-Warning "Packages file '$Path' contains only whitespace. No packages will be processed."
        return @()
    }

    # If we have content, pass it to the parser
    return Parse-PackagesYamlLines -Lines @($lines)
}

# ── DSC parsing (existing configuration.dsc.yaml) ─────────────────────────────

function Read-DscEnsureMap
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

    $map = @{}
    if (-not (Test-Path $Path))
    { return $map # Return empty hash table if file doesn't exist
    }

    $lines = Get-Content -Path $Path -Encoding UTF8

    # Defensive check for null or empty content from Get-Content
    if ($lines -eq $null -or $lines.Length -eq 0)
    {
        Write-Verbose "Read-DscEnsureMap: No content found in '$Path'."
        return $map
    }

    $inBlock = $false
    $blockId = $null
    $blockEnsure = 'Present' # Default

    $resourceStart = [regex]'^\s*-\s*resource:\s*Microsoft\.WinGet\.DSC/WinGetPackage\s*$'
    $idRegex = [regex]'^\s*id:\s*(\S+)\s*$'
    $ensureRegex = [regex]'^\s*ensure:\s*(\S+)\s*$'

    foreach ($line in $lines)
    {
        if ($resourceStart.IsMatch($line))
        {
            # Commit the prior block
            if ($inBlock -and $blockId)
            {
                $map[$blockId] = $blockEnsure
            }

            # Start a new block
            $inBlock = $true
            $blockId = $null
            $blockEnsure = 'Present'
            continue
        }

        if (-not $inBlock)
        { continue
        }

        $mId = $idRegex.Match($line)
        if ($mId.Success)
        {
            $blockId = $mId.Groups[1].Value
            continue
        }

        $mEnsure = $ensureRegex.Match($line)
        if ($mEnsure.Success)
        {
            $blockEnsure = $mEnsure.Groups[1].Value
            continue
        }
    }

    # Commit final block
    if ($inBlock -and $blockId)
    {
        $map[$blockId] = $blockEnsure
    }

    return $map
}

# ── WSL special-case (web-download + winget pin) ──────────────────────────────
#
# winget's Microsoft.WSL MSIX installer fails with 0x80073d28 when administrator
# privileges are required. Keep the WinGetPackage resource for install/uninstall
# tracking, and add a Script resource that updates via `wsl --update --web-download`
# and pins Microsoft.WSL so `winget upgrade --all` skips the broken path.

$WSL_PACKAGE_ID = 'Microsoft.WSL'

function Add-YamlBlockScalar
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Text.StringBuilder]$Builder,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Value,
        [int]$KeyIndent = 8
    )

    $keyPad = ' ' * $KeyIndent
    $bodyPad = ' ' * ($KeyIndent + 2)
    $null = $Builder.AppendLine("${keyPad}${Key}: |")

    $normalized = $Value -replace "`r`n", "`n" -replace "`r", "`n"
    foreach ($line in $normalized.TrimEnd("`n").Split("`n"))
    {
        $null = $Builder.AppendLine("$bodyPad$line")
    }
}

function Get-WslUpdateGetScript
{
    @'
$ErrorActionPreference = "Continue"
$ver = ""
$pinned = $false
try {
    $wsl = Join-Path $env:SystemRoot "System32\wsl.exe"
    if (Test-Path -LiteralPath $wsl) {
        $out = (& $wsl --version 2>&1 | Out-String) -replace "`0", ""
        if ($out -match "WSL version:\s*(\S+)") { $ver = $Matches[1] }
    }
    $pins = & winget pin list --disable-interactivity 2>&1 | Out-String
    if ($pins -match "Microsoft\.WSL") { $pinned = $true }
} catch {
}
return @{ Result = "version=$ver;pinned=$pinned" }
'@
}

function Get-WslUpdateTestScript
{
    @'
$ErrorActionPreference = "Continue"
try {
    $wsl = Join-Path $env:SystemRoot "System32\wsl.exe"
    if (-not (Test-Path -LiteralPath $wsl)) { return $false }
    $verOut = (& $wsl --version 2>&1 | Out-String) -replace "`0", ""
    if ($verOut -notmatch "WSL version:\s*([\d.]+)") { return $false }
    $installed = $Matches[1]
    $pins = & winget pin list --disable-interactivity 2>&1 | Out-String
    if ($pins -notmatch "Microsoft\.WSL") { return $false }
    $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/WSL/releases/latest" -Headers @{ "User-Agent" = "winget-configure" } -UseBasicParsing
    $latest = ([string]$rel.tag_name).TrimStart("v")
    $iParts = New-Object System.Collections.Generic.List[int]
    $lParts = New-Object System.Collections.Generic.List[int]
    foreach ($p in $installed.Split(".")) { if ($p -match "^\d+$") { $iParts.Add([int]$p) } }
    foreach ($p in $latest.Split(".")) { if ($p -match "^\d+$") { $lParts.Add([int]$p) } }
    while ($iParts.Count -lt 4) { $iParts.Add(0) }
    while ($lParts.Count -lt 4) { $lParts.Add(0) }
    for ($n = 0; $n -lt 4; $n++) {
        if ($iParts[$n] -lt $lParts[$n]) { return $false }
        if ($iParts[$n] -gt $lParts[$n]) { return $true }
    }
    return $true
} catch {
    return $false
}
'@
}

function Get-WslUpdateSetScript
{
    @'
$ErrorActionPreference = "Stop"
$wsl = Join-Path $env:SystemRoot "System32\wsl.exe"
if (-not (Test-Path -LiteralPath $wsl)) {
    throw "wsl.exe was not found under System32"
}
$null = & $wsl --update --web-download 2>&1
if ($LASTEXITCODE -ne 0) {
    $null = & $wsl --install --no-distribution --web-download 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "WSL web-download failed with exit $LASTEXITCODE"
    }
}
$pins = & winget pin list --disable-interactivity 2>&1 | Out-String
if ($pins -notmatch "Microsoft\.WSL") {
    $null = & winget pin add --id Microsoft.WSL --exact --blocking --disable-interactivity --accept-source-agreements 2>&1
}
'@
}

function Get-WslUnpinGetScript
{
    @'
$ErrorActionPreference = "Continue"
$pinned = $false
try {
    $pins = & winget pin list --disable-interactivity 2>&1 | Out-String
    if ($pins -match "Microsoft\.WSL") { $pinned = $true }
} catch {
}
return @{ Result = "pinned=$pinned" }
'@
}

function Get-WslUnpinTestScript
{
    @'
$ErrorActionPreference = "Continue"
try {
    $pins = & winget pin list --disable-interactivity 2>&1 | Out-String
    return ($pins -notmatch "Microsoft\.WSL")
} catch {
    return $true
}
'@
}

function Get-WslUnpinSetScript
{
    @'
$ErrorActionPreference = "Continue"
$pins = & winget pin list --disable-interactivity 2>&1 | Out-String
if ($pins -match "Microsoft\.WSL") {
    $null = & winget pin remove --id Microsoft.WSL --exact --disable-interactivity 2>&1
}
'@
}

function Add-WslScriptResource
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][System.Text.StringBuilder]$Builder,
        [Parameter(Mandatory)][string]$ResourceId,
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][string]$GetScript,
        [Parameter(Mandatory)][string]$TestScript,
        [Parameter(Mandatory)][string]$SetScript
    )

    $null = $Builder.AppendLine('')
    $null = $Builder.AppendLine('    - resource: PSDscResources/Script')
    $null = $Builder.AppendLine("      id: $ResourceId")
    $null = $Builder.AppendLine('      directives:')
    $null = $Builder.AppendLine("        description: $Description")
    $null = $Builder.AppendLine('        allowPrerelease: true')
    $null = $Builder.AppendLine('      settings:')
    Add-YamlBlockScalar -Builder $Builder -Key 'GetScript' -Value $GetScript
    Add-YamlBlockScalar -Builder $Builder -Key 'TestScript' -Value $TestScript
    Add-YamlBlockScalar -Builder $Builder -Key 'SetScript' -Value $SetScript
}

# ── DSC YAML builder ──────────────────────────────────────────────────────────

function Build-DscYaml
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[hashtable]]$Entries,

        [Parameter(Mandatory)]
        [string]$SourceFile
    )

    $sb = New-Object System.Text.StringBuilder
    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    $sourceLeaf = Split-Path $SourceFile -Leaf

    $null = $sb.AppendLine($DSC_SCHEMA_COMMENT)
    $null = $sb.AppendLine("# Generated by New-WingetConfiguration.ps1 on $timestamp")
    $null = $sb.AppendLine("# Source of truth: $sourceLeaf  -- DO NOT EDIT MANUALLY")
    $null = $sb.AppendLine('#')
    $null = $sb.AppendLine('# Usage:')
    $null = $sb.AppendLine('#   winget configure -f .configurations\configuration.dsc.yaml')
    $null = $sb.AppendLine('')
    $null = $sb.AppendLine('properties:')
    $null = $sb.AppendLine("  configurationVersion: $DSC_SCHEMA_VERSION")
    $null = $sb.AppendLine('  resources:')

    $lastCategory = $null

    foreach ($entry in $Entries)
    {
        if ($entry.Category -ne $lastCategory)
        {
            $null = $sb.AppendLine('')
            $null = $sb.AppendLine("    # -- $($entry.Category) ----------------------------------------------------------------")
            $lastCategory = $entry.Category
        }

        $desc = if ($entry.Comment -and $entry.Comment.Trim() -ne '')
        { $entry.Comment
        } else
        { $entry.Id
        }
        $ensure = if ($entry.Ensure -and $entry.Ensure.Trim() -ne '')
        { $entry.Ensure
        } else
        { 'Present'
        }

        $null = $sb.AppendLine('')
        $null = $sb.AppendLine('    - resource: Microsoft.WinGet.DSC/WinGetPackage')
        $null = $sb.AppendLine('      directives:')
        $null = $sb.AppendLine("        description: $desc")
        $null = $sb.AppendLine('        allowPrerelease: true')
        $null = $sb.AppendLine('      settings:')
        $null = $sb.AppendLine("        id: $($entry.Id)")
        $null = $sb.AppendLine('        source: winget')
        $null = $sb.AppendLine("        ensure: $ensure")

        if ($entry.Id -eq $WSL_PACKAGE_ID -and $ensure -eq 'Present')
        {
            Add-WslScriptResource -Builder $sb `
                -ResourceId 'Microsoft.WSL.WebUpdate' `
                -Description 'Update WSL via web-download and pin Microsoft.WSL (avoids winget 0x80073d28)' `
                -GetScript (Get-WslUpdateGetScript) `
                -TestScript (Get-WslUpdateTestScript) `
                -SetScript (Get-WslUpdateSetScript)
        }
        elseif ($entry.Id -eq $WSL_PACKAGE_ID -and $ensure -eq 'Absent')
        {
            Add-WslScriptResource -Builder $sb `
                -ResourceId 'Microsoft.WSL.Unpin' `
                -Description 'Remove the Microsoft.WSL winget pin after uninstall' `
                -GetScript (Get-WslUnpinGetScript) `
                -TestScript (Get-WslUnpinTestScript) `
                -SetScript (Get-WslUnpinSetScript)
        }
    }

    return $sb.ToString()
}

# ── Main ──────────────────────────────────────────────────────────────────────

Write-Host '=== WinGet Configuration Generator ===' -ForegroundColor Cyan
Write-Host ''

# Resolve default paths relative to this script's directory
if ([string]::IsNullOrWhiteSpace($PackagesFile))
{
    $PackagesFile = Join-Path $PSScriptRoot 'winget-packages.yml'
}
if ([string]::IsNullOrWhiteSpace($OutputFile))
{
    $OutputFile = Join-Path $PSScriptRoot '.configurations\configuration.dsc.yaml'
}

# Step 0: Parse current YAML
Write-Info "Reading current packages from: $PackagesFile"
$currentEntries = Read-PackagesYaml -Path $PackagesFile
if ($currentEntries.Count -eq 0)
{
    # This warning is already handled within Read-PackagesYaml, but we'll throw here if it still returns empty.
    throw "No packages found or processed from '$PackagesFile'."
}

# Build current ID set (case-sensitive)
$currentIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
foreach ($e in $currentEntries)
{ $null = $currentIds.Add([string]$e.Id)
}

# Step 1: Load previous YAML (Git HEAD)
$prevEntries = New-Object System.Collections.Generic.List[hashtable]
$prevIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)

$gitAvailable = Test-GitAvailable
if (-not $gitAvailable)
{
    Write-Warn 'Git is not available. Removed-package tracking will be skipped.'
} else
{
    $packagesDir = (Split-Path -Parent (Resolve-Path -Path $PackagesFile).Path)
    $repoRoot = Get-GitRepoRoot -StartDirectory $packagesDir

    if (-not $repoRoot)
    {
        Write-Warn "Could not locate Git repo root. Removed-package tracking will be skipped."
    } else
    {
        $relPath = Get-RelativePath -BasePath $repoRoot -TargetPath (Resolve-Path -Path $PackagesFile).Path
        Write-Info "Comparing against: ${CompareRef}:$($relPath.Replace('\','/'))"

        $prevContent = Get-GitFileContentAtRef -RepoRoot $repoRoot -RepoRelativePath $relPath -Ref $CompareRef
        if ($null -eq $prevContent)
        {
            Write-Warn "Could not read previous file content from Git '$CompareRef'. Removed-package tracking will be skipped."
        } else
        {
            # PowerShell may return a single string or string[] depending on output
            $prevLines = @()
            if ($prevContent -is [string])
            {
                $prevLines = $prevContent -split "`r?`n"
            } else
            {
                $prevLines = [string[]]$prevContent
            }

            # Ensure $prevLines is not null or empty before parsing
            if ($prevLines -ne $null -and $prevLines.Length -gt 0)
            {
                $parsedPrev = Parse-PackagesYamlLines -Lines $prevLines
                foreach ($p in $parsedPrev)
                { $prevEntries.Add($p)
                }

                foreach ($p in $prevEntries)
                { $null = $prevIds.Add([string]$p.Id)
                }
            } else
            {
                Write-Warning "Previous Git content for '$relPath' was empty or null after splitting lines. No previous packages loaded."
            }
        }
    }
}

# Step 2: Read existing DSC ensures (for pruning stale Absent)
$existingEnsure = Read-DscEnsureMap -Path $OutputFile

# Step 3: Determine removals and pruning
$removedIds = New-Object 'System.Collections.Generic.List[string]'
foreach ($id in $prevIds)
{
    if (-not $currentIds.Contains($id))
    {
        $removedIds.Add($id) | Out-Null
    }
}

# Stale Absent pruning:
# If existing has ensure: Absent, and the package is NOT in previous YAML (HEAD),
# and NOT in current YAML (working tree), then remove it entirely.
$prunedIds = New-Object 'System.Collections.Generic.List[string]'
foreach ($kv in $existingEnsure.GetEnumerator())
{
    $id = [string]$kv.Key
    $ensure = [string]$kv.Value

    if ($ensure -eq 'Absent' -and (-not $currentIds.Contains($id)) -and (-not $prevIds.Contains($id)))
    {
        $prunedIds.Add($id) | Out-Null
    }
}

$prunedSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
foreach ($id in $prunedIds)
{ $null = $prunedSet.Add($id)
}

# Step 4: Build desired entries list (stable order)
$finalEntries = New-Object System.Collections.Generic.List[hashtable]

# Present: in current YAML (in order)
foreach ($e in $currentEntries)
{
    $finalEntries.Add(@{
            Id       = $e.Id
            Category = $e.Category
            Comment  = $e.Comment
            Ensure   = 'Present'
        }) | Out-Null
}

# Absent tombstones: in prev YAML but removed now (in prev order)
if ($removedIds.Count -gt 0)
{
    foreach ($e in $prevEntries)
    {
        $id = [string]$e.Id
        if ($currentIds.Contains($id))
        { continue
        }
        if (-not $prevIds.Contains($id))
        { continue
        } # defensive
        if ($prunedSet.Contains($id))
        { continue
        }    # if somehow stale (shouldn't be), prune wins

        $finalEntries.Add(@{
                Id       = $e.Id
                Category = $e.Category
                Comment  = $e.Comment
                Ensure   = 'Absent'
            }) | Out-Null
    }
}

# Step 5: Ensure output directory exists
$outputDir = Split-Path $OutputFile -Parent
if (-not (Test-Path $outputDir))
{
    Write-Info "Creating output directory: $outputDir"
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# Step 6: Guard against accidental overwrites
if ((Test-Path $OutputFile) -and -not $Force)
{
    $answer = Read-Host "Output file already exists: $OutputFile`nOverwrite? [y/N]"
    if ($answer -notmatch '^[Yy]')
    {
        Write-Warn 'Aborted by user. Use -Force to suppress this prompt.'
        exit 0
    }
}

# Step 7: Summary
# Added IDs are current - previous
$addedIds = New-Object 'System.Collections.Generic.List[string]'
foreach ($id in $currentIds)
{
    if (-not $prevIds.Contains($id))
    {
        $addedIds.Add($id) | Out-Null
    }
}

Write-Host ''
Write-Host '=== Change Summary (vs Git HEAD) ===' -ForegroundColor Cyan
Write-Host ("Current YAML packages : {0}" -f $currentEntries.Count) -ForegroundColor White
if ($prevIds.Count -gt 0)
{
    Write-Host ("Previous YAML packages: {0}" -f $prevIds.Count) -ForegroundColor White
} else
{
    Write-Host "Previous YAML packages: (unknown / unavailable)" -ForegroundColor Yellow
}
Write-Host ("Added (Present)       : {0}" -f $addedIds.Count) -ForegroundColor Green
Write-Host ("Removed -> Absent      : {0}" -f $removedIds.Count) -ForegroundColor Yellow
Write-Host ("Pruned stale Absent    : {0}" -f $prunedIds.Count) -ForegroundColor Gray
Write-Host ''

# Step 7b: Write machine-readable changes file (for CI consumption)
if (-not [string]::IsNullOrWhiteSpace($ChangesOutputFile))
{
    $changesData = @{
        added   = @($addedIds | ForEach-Object { $_.ToString() })
        removed = @($removedIds | ForEach-Object { $_.ToString() })
        pruned  = @($prunedIds | ForEach-Object { $_.ToString() })
        total   = $finalEntries.Count
    }
    $changesJson = $changesData | ConvertTo-Json -Depth 3
    [System.IO.File]::WriteAllText($ChangesOutputFile, $changesJson, [System.Text.Encoding]::UTF8)
    Write-Success "Changes written to: $ChangesOutputFile"
}

# Step 8: Build and write the DSC YAML
Write-Info 'Generating DSC YAML...'
$yaml = Build-DscYaml -Entries $finalEntries -SourceFile $PackagesFile

if ($PSCmdlet.ShouldProcess($OutputFile, 'Write DSC configuration'))
{
    [System.IO.File]::WriteAllText($OutputFile, $yaml, [System.Text.Encoding]::UTF8)
    Write-Success "Written to: $OutputFile"
}

Write-Host ''
Write-Host 'To apply the configuration, run:' -ForegroundColor Gray
Write-Host "  winget configure -f `"$OutputFile`"" -ForegroundColor White
Write-Host ''
Write-Success 'Done.'
