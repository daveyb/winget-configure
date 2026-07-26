#Requires -Version 5.1
<#
.SYNOPSIS
    Generates a single winget-configure DSC YAML file from winget-packages.yml,
    tracking removals and pruning stale 'Absent' entries.

.DESCRIPTION
    Reads the current winget-packages.yml and compares it against a previous
    version of that same file in Git (configurable via -CompareRef, default HEAD).

    Emits .configurations/configuration.dsc.yaml:

    - Packages present in the current YAML get ensure: Present.
    - Packages removed from the current YAML but present in the previous ref
      are emitted with ensure: Absent (tombstone).
    - Stale Absent entries (not in previous or current YAML) are pruned.

.PARAMETER PackagesFile
    Path to the source YAML file. Defaults to winget-packages.yml next to this script.

.PARAMETER OutputFile
    Path for the generated DSC YAML. Defaults to .configurations\configuration.dsc.yaml.

.PARAMETER Force
    Overwrites the output file without prompting if it already exists.

.PARAMETER CompareRef
    Git reference to compare against. Defaults to HEAD.

.PARAMETER ChangesOutputFile
    Optional path for machine-readable JSON of changes (added, removed, pruned).

.EXAMPLE
    .\New-WingetConfiguration.ps1 -Force

.EXAMPLE
    .\New-WingetConfiguration.ps1 -Force -CompareRef HEAD~1 -ChangesOutputFile changes.json
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

Import-Module (Join-Path $PSScriptRoot 'helpers\PackagesYaml.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'helpers\DscConfiguration.psm1') -Force

function Write-Info
{
    param([string]$Message)
    Write-Host $Message -ForegroundColor Blue
}

function Write-Success
{
    param([string]$Message)
    Write-Host $Message -ForegroundColor Green
}

function Get-RelativePath
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BasePath,
        [Parameter(Mandatory)][string]$TargetPath
    )

    $baseFull = (Resolve-Path -LiteralPath $BasePath).Path.TrimEnd('\') + '\'
    $targetFull = (Resolve-Path -LiteralPath $TargetPath).Path

    $baseUri = New-Object System.Uri($baseFull)
    $targetUri = New-Object System.Uri($targetFull)
    $relUri = $baseUri.MakeRelativeUri($targetUri)
    $rel = [System.Uri]::UnescapeDataString($relUri.ToString())
    return $rel.Replace('/', '\')
}

function Test-GitAvailable
{
    try
    {
        $null = & git --version 2>$null
        return ($LASTEXITCODE -eq 0)
    }
    catch
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
    }
    catch
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
        [Parameter(Mandatory)][string]$Ref
    )

    $gitPath = $RepoRelativePath.Replace('\', '/')
    $spec = "${Ref}:${gitPath}"

    try
    {
        $content = & git -C $RepoRoot show $spec 2>$null
        if ($LASTEXITCODE -eq 0)
        {
            return $content
        }
    }
    catch
    {
        Write-Warning "Git command failed: $($_.Exception.Message)"
    }

    return $null
}

function Get-PreviousPackageEntries
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PackagesFilePath,
        [Parameter(Mandatory)][string]$Ref
    )

    if (-not (Test-GitAvailable))
    {
        Write-Warning 'Git is not available. Removed-package tracking will be skipped.'
        return @()
    }

    $packagesDir = Split-Path -Parent (Resolve-Path -LiteralPath $PackagesFilePath).Path
    $repoRoot = Get-GitRepoRoot -StartDirectory $packagesDir
    if (-not $repoRoot)
    {
        Write-Warning 'Could not locate Git repo root. Removed-package tracking will be skipped.'
        return @()
    }

    $relPath = Get-RelativePath -BasePath $repoRoot -TargetPath (Resolve-Path -LiteralPath $PackagesFilePath).Path
    $relForward = $relPath.Replace('\', '/')
    Write-Info "Comparing against: ${Ref}:$relForward"

    $prevContent = Get-GitFileContentAtRef -RepoRoot $repoRoot -RepoRelativePath $relPath -Ref $Ref
    if ($null -eq $prevContent)
    {
        Write-Warning "Could not read previous file content from Git '$Ref'. Removed-package tracking will be skipped."
        return @()
    }

    $prevLines = @()
    if ($prevContent -is [string])
    {
        $prevLines = $prevContent -split "`r?`n"
    }
    else
    {
        $prevLines = [string[]]$prevContent
    }

    if ($null -eq $prevLines -or $prevLines.Length -eq 0)
    {
        Write-Warning "Previous Git content for '$relPath' was empty. No previous packages loaded."
        return @()
    }

    return @(Parse-PackagesYamlLines -Lines $prevLines)
}

# ── Main ──────────────────────────────────────────────────────────────────────

Write-Host '=== WinGet Configuration Generator ===' -ForegroundColor Cyan
Write-Host ''

if ([string]::IsNullOrWhiteSpace($PackagesFile))
{
    $PackagesFile = Join-Path $PSScriptRoot 'winget-packages.yml'
}
if ([string]::IsNullOrWhiteSpace($OutputFile))
{
    $OutputFile = Join-Path $PSScriptRoot '.configurations\configuration.dsc.yaml'
}

Write-Info "Reading current packages from: $PackagesFile"
$currentEntries = @(Read-PackagesYaml -Path $PackagesFile)
if ($currentEntries.Count -eq 0)
{
    throw "No packages found or processed from '$PackagesFile'."
}

$previousEntries = @(Get-PreviousPackageEntries -PackagesFilePath $PackagesFile -Ref $CompareRef)
$existingEnsure = Read-DscEnsureMap -Path $OutputFile

$lifecycle = Resolve-PackageLifecycle `
    -CurrentEntries $currentEntries `
    -PreviousEntries $previousEntries `
    -ExistingEnsure $existingEnsure

$finalEntries = $lifecycle.FinalEntries
$addedIds = $lifecycle.AddedIds
$removedIds = $lifecycle.RemovedIds
$prunedIds = $lifecycle.PrunedIds

$outputDir = Split-Path $OutputFile -Parent
if (-not (Test-Path -LiteralPath $outputDir))
{
    Write-Info "Creating output directory: $outputDir"
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

if ((Test-Path -LiteralPath $OutputFile) -and -not $Force)
{
    $answer = Read-Host "Output file already exists: $OutputFile`nOverwrite? [y/N]"
    if ($answer -notmatch '^[Yy]')
    {
        Write-Warning 'Aborted by user. Use -Force to suppress this prompt.'
        exit 0
    }
}

Write-Host ''
Write-Host "=== Change Summary (vs Git $CompareRef) ===" -ForegroundColor Cyan
Write-Host ("Current YAML packages : {0}" -f $currentEntries.Count) -ForegroundColor White
if ($previousEntries.Count -gt 0)
{
    Write-Host ("Previous YAML packages: {0}" -f $previousEntries.Count) -ForegroundColor White
}
else
{
    Write-Host 'Previous YAML packages: (unknown / unavailable)' -ForegroundColor Yellow
}
Write-Host ("Added (Present)       : {0}" -f $addedIds.Count) -ForegroundColor Green
Write-Host ("Removed -> Absent     : {0}" -f $removedIds.Count) -ForegroundColor Yellow
Write-Host ("Pruned stale Absent   : {0}" -f $prunedIds.Count) -ForegroundColor Gray
Write-Host ''

if (-not [string]::IsNullOrWhiteSpace($ChangesOutputFile))
{
    $changesData = @{
        added   = @($addedIds | ForEach-Object { $_.ToString() })
        removed = @($removedIds | ForEach-Object { $_.ToString() })
        pruned  = @($prunedIds | ForEach-Object { $_.ToString() })
        total   = $finalEntries.Count
    }
    $changesJson = $changesData | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($ChangesOutputFile, $changesJson, [System.Text.UTF8Encoding]::new($false))
    Write-Success "Changes written to: $ChangesOutputFile"
}

Write-Info 'Generating DSC YAML...'
$yaml = Build-DscYaml -Entries @($finalEntries) -SourceFile $PackagesFile

# Skip write when content is unchanged (stable output, no timestamp noise)
$shouldWrite = $true
if (Test-Path -LiteralPath $OutputFile)
{
    $existing = [System.IO.File]::ReadAllText($OutputFile)
    # Normalize line endings for comparison
    $existingNorm = $existing -replace "`r`n", "`n"
    $yamlNorm = $yaml -replace "`r`n", "`n"
    if ($existingNorm -eq $yamlNorm)
    {
        $shouldWrite = $false
        Write-Success "No content changes: $OutputFile"
    }
}

if ($shouldWrite -and $PSCmdlet.ShouldProcess($OutputFile, 'Write DSC configuration'))
{
    [System.IO.File]::WriteAllText($OutputFile, $yaml, [System.Text.UTF8Encoding]::new($false))
    Write-Success "Written to: $OutputFile"
}

Write-Host ''
Write-Host 'To apply the configuration, run:' -ForegroundColor Gray
Write-Host "  winget configure -f `"$OutputFile`"" -ForegroundColor White
Write-Host ''
Write-Success 'Done.'
