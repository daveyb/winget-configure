#Requires -Version 5.1
<#
.SYNOPSIS
    Shared parser for winget-packages.yml (subset of YAML used by this repo).

.DESCRIPTION
    Parses the package list without external module dependencies.
    Category keys are used as category names; decorative comment headers
    (e.g. "# -- Development tools --") override the display name for the
    following section when present.
#>

Set-StrictMode -Version Latest

function ConvertTo-CategoryDisplayName
{
    <#
    .SYNOPSIS
        Turns a YAML key such as cloud_infrastructure into a display label.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key
    )

    $parts = $Key -split '[_-]+' | Where-Object { $_ -ne '' }
    $titled = foreach ($p in $parts)
    {
        if ($p.Length -eq 0) { continue }
        $p.Substring(0, 1).ToUpperInvariant() + $p.Substring(1)
    }
    return ($titled -join ' ')
}

function ConvertFrom-PackagesYaml
{
    <#
    .SYNOPSIS
        Parse winget-packages.yml lines into package entry hashtables.

    .OUTPUTS
        Zero or more hashtables with keys: Id, Category, Comment, AllowPrerelease.
        Callers should wrap with @() to materialize an array.
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()]
        [AllowNull()]
        [string[]]$Lines = @()
    )

    if ($null -eq $Lines -or $Lines.Count -eq 0)
    {
        Write-Verbose 'ConvertFrom-PackagesYaml received null or empty Lines array.'
        return
    }

    $entries = New-Object System.Collections.Generic.List[hashtable]
    $currentCategory = 'Uncategorised'
    $pendingDisplayName = $null
    $inPackages = $false

    foreach ($rawLine in $Lines)
    {
        if ([string]::IsNullOrWhiteSpace($rawLine))
        {
            continue
        }

        # Decorative headers like: "# -- Development tools & languages ----"
        # Applied when the following category key is seen (preferred display name).
        if ($rawLine -match '^\s*#\s*[^\w\s]+\s+(.+?)\s+[^\w\s]+\s*$')
        {
            $pendingDisplayName = $Matches[1].Trim()
            continue
        }

        # Other comments
        if ($rawLine -match '^\s*#')
        {
            continue
        }

        if ($rawLine -match '^\s*packages\s*:\s*$')
        {
            $inPackages = $true
            continue
        }

        if (-not $inPackages)
        {
            continue
        }

        # Category keys like "  development:" — use decorative header when present, else humanize key
        if ($rawLine -match '^\s{2,}([\w-]+)\s*:\s*$')
        {
            $key = $Matches[1]
            if ($pendingDisplayName)
            {
                $currentCategory = $pendingDisplayName
                $pendingDisplayName = $null
            }
            else
            {
                $currentCategory = ConvertTo-CategoryDisplayName -Key $key
            }
            continue
        }

        # Package list items:
        #   - Git.Git
        #   - Git.Git # comment
        #   - Git.Git # comment @prerelease
        if ($rawLine -match '^\s*-\s+([^\s#]+)(?:\s+#\s*(.*))?\s*$')
        {
            $id = $Matches[1].Trim()
            $comment = ''
            if ($Matches.Count -ge 3 -and $null -ne $Matches[2])
            {
                $comment = $Matches[2].Trim()
            }

            $allowPrerelease = $false
            if ($comment -match '@prerelease\b')
            {
                $allowPrerelease = $true
                $comment = ($comment -replace '@prerelease\b', '').Trim()
                $comment = ($comment -replace '\s{2,}', ' ').Trim()
            }

            if (-not [string]::IsNullOrWhiteSpace($id))
            {
                $entries.Add(@{
                        Id              = $id
                        Category        = $currentCategory
                        Comment         = $comment
                        AllowPrerelease = $allowPrerelease
                    })
            }
        }
    }

    # Enumerate so callers can reliably do: $items = @(ConvertFrom-PackagesYaml ...)
    foreach ($entry in $entries)
    {
        $entry
    }
}

# Back-compat alias used by New-WingetConfiguration.ps1 and tests
Set-Alias -Name Parse-PackagesYamlLines -Value ConvertFrom-PackagesYaml

function Get-PackagesYaml
{
    <#
    .SYNOPSIS
        Read and parse a winget-packages.yml file.

    .PARAMETER Path
        Full path to the YAML file.

    .OUTPUTS
        Package entry hashtables (Id, Category, Comment, AllowPrerelease).
        Callers should wrap with @() to materialize an array.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path))
    {
        throw "Packages file not found: $Path"
    }

    $lines = Get-Content -LiteralPath $Path -Encoding UTF8

    if ($null -eq $lines -or $lines.Length -eq 0)
    {
        Write-Warning "Packages file '$Path' returned no content. No packages will be processed."
        return
    }

    if (($lines -join '') -match '^\s*$')
    {
        Write-Warning "Packages file '$Path' contains only whitespace. No packages will be processed."
        return
    }

    ConvertFrom-PackagesYaml -Lines @($lines)
}

# Back-compat alias
Set-Alias -Name Read-PackagesYaml -Value Get-PackagesYaml

function Get-PackageIdList
{
    <#
    .SYNOPSIS
        Return a flat string[] of package IDs from a packages YAML file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $entries = @(Get-PackagesYaml -Path $Path)
    foreach ($e in $entries)
    {
        [string]$e.Id
    }
}

Export-ModuleMember -Function ConvertFrom-PackagesYaml, Get-PackagesYaml, Get-PackageIdList, ConvertTo-CategoryDisplayName -Alias Parse-PackagesYamlLines, Read-PackagesYaml
