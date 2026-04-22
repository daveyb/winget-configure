#Requires -Version 5.1
<#
.SYNOPSIS
    Generates a single winget-configure DSC YAML file from winget-packages.yml.

.DESCRIPTION
    Reads the categorised package list in winget-packages.yml and emits a single
    .configurations/configuration.dsc.yaml file containing one
    Microsoft.WinGet.DSC/WinGetPackage resource block per package.

    The generated file is idempotent by design: every resource defaults to
    ensure: Present, so running `winget configure` repeatedly will only install
    packages that are not already present on the machine.

    Run this script whenever winget-packages.yml changes, then commit the
    generated configuration.dsc.yaml alongside it.

.PARAMETER PackagesFile
    Path to the source YAML file.  Defaults to winget-packages.yml next to
    this script.

.PARAMETER OutputFile
    Path to write the generated DSC YAML file.  Defaults to
    .configurations\configuration.dsc.yaml next to this script.

.PARAMETER Force
    Overwrites the output file without prompting if it already exists.

.EXAMPLE
    .\New-WingetConfiguration.ps1
    Generates .configurations\configuration.dsc.yaml from winget-packages.yml.

.EXAMPLE
    .\New-WingetConfiguration.ps1 -Force
    Regenerates the output file without prompting.

.EXAMPLE
    .\New-WingetConfiguration.ps1 -PackagesFile C:\custom\packages.yml -OutputFile C:\out\config.dsc.yaml
    Uses custom input/output paths.

.NOTES
    The generated file is intended to be run with:
        winget configure -f .configurations\configuration.dsc.yaml
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$PackagesFile,

    [string]$OutputFile,

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Constants ─────────────────────────────────────────────────────────────────

$DSC_SCHEMA_COMMENT = '# yaml-language-server: $schema=https://aka.ms/configuration-dsc-schema/0.2'
$DSC_SCHEMA_VERSION = '0.2.0'

# ── Helpers ───────────────────────────────────────────────────────────────────

function Write-Info
{ param([string]$m) Write-Host $m -ForegroundColor Blue
}
function Write-Success
{ param([string]$m) Write-Host $m -ForegroundColor Green
}
function Write-Warn
{ param([string]$m) Write-Warning $m
}

# ── YAML parser ───────────────────────────────────────────────────────────────
#
# Parses the specific subset of YAML used in winget-packages.yml:
#
#   packages:
#     category_name:        <- category header, captured as current section
#       - PackageId         <- list item, collected with its section label
#       - PackageId  # comment
#
# Returns an ordered list of [hashtable] with keys:
#   Category  – human-readable section name (e.g. "Development tools & languages")
#   Id        – winget package ID
#   Comment   – inline comment text, or empty string

function Read-PackagesYaml
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path))
    {
        Write-Error "Packages file not found: $Path"
        return @()
    }

    $entries         = [System.Collections.Generic.List[hashtable]]::new()
    $currentCategory = 'Uncategorised'
    $inPackages      = $false

    foreach ($rawLine in Get-Content -Path $Path -Encoding UTF8)
    {

        # ── blank lines ───────────────────────────────────────────────────────
        if ([string]::IsNullOrWhiteSpace($rawLine))
        { continue
        }

        # ── top-level and category comment headers  ───────────────────────────
        # Capture decorative section comments like:
        #   # ── Development tools & languages ───────────────────────────────
        if ($rawLine -match '^\s*#\s*[─━─]+\s*(.+?)\s*[─━─]+')
        {
            $currentCategory = $Matches[1].Trim()
            continue
        }

        # Skip all other pure-comment lines
        if ($rawLine -match '^\s*#')
        { continue
        }

        # ── detect entry into the packages: block ─────────────────────────────
        if ($rawLine -match '^packages\s*:')
        {
            $inPackages = $true
            continue
        }

        if (-not $inPackages)
        { continue
        }

        # ── category key (two-space indent, no leading dash) ──────────────────
        # e.g. "  development:" or "  cloud_infrastructure:"
        if ($rawLine -match '^\s{2,}(\w+)\s*:\s*$')
        {
            # Use the comment-derived label if we already have a good one;
            # otherwise fall back to the key name.
            # (The decorative comment always appears immediately before the key.)
            continue
        }

        # ── list items ────────────────────────────────────────────────────────
        # e.g. "    - Git.Git # Git version control"
        if ($rawLine -match '^\s+-\s+(\S+)(?:\s+#\s*(.*))?')
        {
            $packageId = $Matches[1].Trim()
            $comment   = if ($Matches.Count -ge 3)
            { $Matches[2].Trim()
            } else
            { ''
            }

            # Strip any trailing inline comment that crept into the ID itself
            $packageId = ($packageId -replace '#.*$', '').Trim()

            if ($packageId -ne '')
            {
                $entries.Add(@{
                        Category = $currentCategory
                        Id       = $packageId
                        Comment  = $comment
                    })
            }
        }
    }

    return $entries
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

    $sb = [System.Text.StringBuilder]::new()

    $timestamp   = (Get-Date).ToString('yyyy-MM-dd HH:mm')
    $sourceLeaf  = Split-Path $SourceFile -Leaf

    $null = $sb.AppendLine($DSC_SCHEMA_COMMENT)
    $null = $sb.AppendLine("# Generated by New-WingetConfiguration.ps1 on $timestamp")
    $null = $sb.AppendLine("# Source of truth: $sourceLeaf  — DO NOT EDIT MANUALLY")
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

        # Emit a category comment banner when the section changes
        if ($entry.Category -ne $lastCategory)
        {
            $null = $sb.AppendLine('')
            $banner = "    # $('─' * 2) $($entry.Category) $('─' * (70 - $entry.Category.Length))"
            $null = $sb.AppendLine($banner)
            $lastCategory = $entry.Category
        }

        # description: prefer the inline comment, fall back to the package ID
        $description = if ($entry.Comment -ne '')
        { $entry.Comment
        } else
        { $entry.Id
        }

        $null = $sb.AppendLine('')
        $null = $sb.AppendLine('    - resource: Microsoft.WinGet.DSC/WinGetPackage')
        $null = $sb.AppendLine('      directives:')
        $null = $sb.AppendLine("        description: $description")
        $null = $sb.AppendLine('        allowPrerelease: true')
        $null = $sb.AppendLine('      settings:')
        $null = $sb.AppendLine("        id: $($entry.Id)")
        $null = $sb.AppendLine('        source: winget')
        $null = $sb.AppendLine('        ensure: Present')
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

# ── Step 1: Parse source YAML ─────────────────────────────────────────────────
Write-Info "Reading packages from: $PackagesFile"

$entries = Read-PackagesYaml -Path $PackagesFile

if ($entries.Count -eq 0)
{
    Write-Error "No packages found in '$PackagesFile'. Aborting."
    exit 1
}

Write-Success "✓ Found $($entries.Count) packages across $(($entries | Select-Object -ExpandProperty Category -Unique).Count) categories"

# ── Step 2: Ensure output directory exists ────────────────────────────────────
$outputDir = Split-Path $OutputFile -Parent
if (-not (Test-Path $outputDir))
{
    Write-Info "Creating output directory: $outputDir"
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# ── Step 3: Guard against accidental overwrites ───────────────────────────────
if ((Test-Path $OutputFile) -and -not $Force)
{
    $answer = Read-Host "Output file already exists: $OutputFile`nOverwrite? [y/N]"
    if ($answer -notmatch '^[Yy]')
    {
        Write-Warn 'Aborted by user. Use -Force to suppress this prompt.'
        exit 0
    }
}

# ── Step 4: Build and write the DSC YAML ─────────────────────────────────────
Write-Info 'Generating DSC YAML...'

$yaml = Build-DscYaml -Entries $entries -SourceFile $PackagesFile

if ($PSCmdlet.ShouldProcess($OutputFile, 'Write DSC configuration'))
{
    [System.IO.File]::WriteAllText($OutputFile, $yaml, [System.Text.Encoding]::UTF8)
    Write-Success "✓ Written to: $OutputFile"
}

Write-Host ''
Write-Host 'To apply the configuration, run:' -ForegroundColor Gray
Write-Host "  winget configure -f `"$OutputFile`"" -ForegroundColor White
Write-Host ''
Write-Success '✓ Done.'
```
