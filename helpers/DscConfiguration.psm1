#Requires -Version 5.1
<#
.SYNOPSIS
    Pure helpers for DSC configuration generation and lifecycle diffing.
#>

Set-StrictMode -Version Latest

$script:DscSchemaComment = '# yaml-language-server: $schema=https://aka.ms/configuration-dsc-schema/0.2'
$script:DscSchemaVersion = '0.2.0'

function Read-DscEnsureMap
{
    <#
    .SYNOPSIS
        Parse an existing configuration.dsc.yaml into id -> ensure map.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $map = @{}
    if (-not (Test-Path -LiteralPath $Path))
    {
        return $map
    }

    $lines = Get-Content -LiteralPath $Path -Encoding UTF8
    if ($null -eq $lines -or $lines.Length -eq 0)
    {
        return $map
    }

    $inBlock = $false
    $blockId = $null
    $blockEnsure = 'Present'

    $resourceStart = [regex]'^\s*-\s*resource:\s*Microsoft\.WinGet\.DSC/WinGetPackage\s*$'
    $idRegex = [regex]'^\s*id:\s*(\S+)\s*$'
    $ensureRegex = [regex]'^\s*ensure:\s*(\S+)\s*$'

    foreach ($line in $lines)
    {
        if ($resourceStart.IsMatch($line))
        {
            if ($inBlock -and $blockId)
            {
                $map[$blockId] = $blockEnsure
            }

            $inBlock = $true
            $blockId = $null
            $blockEnsure = 'Present'
            continue
        }

        if (-not $inBlock)
        {
            continue
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

    if ($inBlock -and $blockId)
    {
        $map[$blockId] = $blockEnsure
    }

    return $map
}

function Resolve-PackageLifecycle
{
    <#
    .SYNOPSIS
        Compute final DSC entries and change sets from current/previous package lists.

    .PARAMETER CurrentEntries
        Package entries from the working-tree YAML.

    .PARAMETER PreviousEntries
        Package entries from the compare Git ref (may be empty).

    .PARAMETER ExistingEnsure
        Map of package id -> ensure from the existing DSC file (for prune).

    .OUTPUTS
        Hashtable with keys: FinalEntries, AddedIds, RemovedIds, PrunedIds
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$CurrentEntries,

        [AllowEmptyCollection()]
        [object[]]$PreviousEntries = @(),

        [hashtable]$ExistingEnsure = @{}
    )

    $currentIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($e in @($CurrentEntries))
    {
        if ($null -ne $e -and $e.Id)
        {
            $null = $currentIds.Add([string]$e.Id)
        }
    }

    $prevIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $prevList = New-Object System.Collections.Generic.List[hashtable]
    foreach ($e in @($PreviousEntries))
    {
        if ($null -eq $e -or -not $e.Id)
        {
            continue
        }
        $null = $prevIds.Add([string]$e.Id)
        $prevList.Add(@{
                Id              = [string]$e.Id
                Category        = $(if ($e.Category) { [string]$e.Category } else { 'Uncategorised' })
                Comment         = $(if ($e.Comment) { [string]$e.Comment } else { '' })
                AllowPrerelease = [bool]($e.AllowPrerelease)
            })
    }

    $removedIds = New-Object 'System.Collections.Generic.List[string]'
    foreach ($id in $prevIds)
    {
        if (-not $currentIds.Contains($id))
        {
            $removedIds.Add($id) | Out-Null
        }
    }

    $prunedIds = New-Object 'System.Collections.Generic.List[string]'
    if ($null -ne $ExistingEnsure)
    {
        foreach ($kv in $ExistingEnsure.GetEnumerator())
        {
            $id = [string]$kv.Key
            $ensure = [string]$kv.Value
            if ($ensure -eq 'Absent' -and (-not $currentIds.Contains($id)) -and (-not $prevIds.Contains($id)))
            {
                $prunedIds.Add($id) | Out-Null
            }
        }
    }

    $prunedSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    foreach ($id in $prunedIds)
    {
        $null = $prunedSet.Add($id)
    }

    $finalEntries = New-Object System.Collections.Generic.List[hashtable]
    foreach ($e in @($CurrentEntries))
    {
        if ($null -eq $e -or -not $e.Id)
        {
            continue
        }
        $finalEntries.Add(@{
                Id              = [string]$e.Id
                Category        = $(if ($e.Category) { [string]$e.Category } else { 'Uncategorised' })
                Comment         = $(if ($e.Comment) { [string]$e.Comment } else { '' })
                AllowPrerelease = [bool]($e.AllowPrerelease)
                Ensure          = 'Present'
            }) | Out-Null
    }

    if ($removedIds.Count -gt 0)
    {
        foreach ($e in $prevList)
        {
            $id = [string]$e.Id
            if ($currentIds.Contains($id))
            {
                continue
            }
            if ($prunedSet.Contains($id))
            {
                continue
            }

            $finalEntries.Add(@{
                    Id              = $e.Id
                    Category        = $e.Category
                    Comment         = $e.Comment
                    AllowPrerelease = $e.AllowPrerelease
                    Ensure          = 'Absent'
                }) | Out-Null
        }
    }

    $addedIds = New-Object 'System.Collections.Generic.List[string]'
    foreach ($id in $currentIds)
    {
        if (-not $prevIds.Contains($id))
        {
            $addedIds.Add($id) | Out-Null
        }
    }

    return @{
        FinalEntries = $finalEntries
        AddedIds     = $addedIds
        RemovedIds   = $removedIds
        PrunedIds    = $prunedIds
    }
}

function Build-DscYaml
{
    <#
    .SYNOPSIS
        Build a stable DSC configuration YAML string from package entries.

    .NOTES
        Output is deterministic for a given entry set (no wall-clock timestamp)
        so regenerating without package changes does not dirty the file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Entries,

        [Parameter(Mandatory)]
        [string]$SourceFile
    )

    $sb = New-Object System.Text.StringBuilder
    $sourceLeaf = Split-Path $SourceFile -Leaf

    $null = $sb.AppendLine($script:DscSchemaComment)
    $null = $sb.AppendLine('# Generated by New-WingetConfiguration.ps1')
    $null = $sb.AppendLine("# Source of truth: $sourceLeaf  -- DO NOT EDIT MANUALLY")
    $null = $sb.AppendLine('#')
    $null = $sb.AppendLine('# Usage:')
    $null = $sb.AppendLine('#   winget configure -f .configurations\configuration.dsc.yaml')
    $null = $sb.AppendLine('')
    $null = $sb.AppendLine('properties:')
    $null = $sb.AppendLine("  configurationVersion: $script:DscSchemaVersion")
    $null = $sb.AppendLine('  resources:')

    $lastCategory = $null

    foreach ($entry in @($Entries))
    {
        if ($null -eq $entry)
        {
            continue
        }

        $category = if ($entry.Category) { [string]$entry.Category } else { 'Uncategorised' }
        if ($category -ne $lastCategory)
        {
            $null = $sb.AppendLine('')
            $null = $sb.AppendLine("    # -- $category ----------------------------------------------------------------")
            $lastCategory = $category
        }

        $desc = if ($entry.Comment -and ([string]$entry.Comment).Trim() -ne '')
        {
            [string]$entry.Comment
        }
        else
        {
            [string]$entry.Id
        }

        $ensure = if ($entry.Ensure -and ([string]$entry.Ensure).Trim() -ne '')
        {
            [string]$entry.Ensure
        }
        else
        {
            'Present'
        }

        $allowPrerelease = if ($entry.PSObject.Properties['AllowPrerelease'] -or ($entry -is [hashtable] -and $entry.ContainsKey('AllowPrerelease')))
        {
            [bool]$entry.AllowPrerelease
        }
        else
        {
            $false
        }
        $allowPrereleaseText = if ($allowPrerelease) { 'true' } else { 'false' }

        $null = $sb.AppendLine('')
        $null = $sb.AppendLine('    - resource: Microsoft.WinGet.DSC/WinGetPackage')
        $null = $sb.AppendLine('      directives:')
        $null = $sb.AppendLine("        description: $desc")
        $null = $sb.AppendLine("        allowPrerelease: $allowPrereleaseText")
        $null = $sb.AppendLine('      settings:')
        $null = $sb.AppendLine("        id: $($entry.Id)")
        $null = $sb.AppendLine('        source: winget')
        $null = $sb.AppendLine("        ensure: $ensure")
    }

    return $sb.ToString()
}

Export-ModuleMember -Function Read-DscEnsureMap, Resolve-PackageLifecycle, Build-DscYaml
