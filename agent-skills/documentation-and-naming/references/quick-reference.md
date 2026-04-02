# Quick Reference — Documentation and Naming Standards

Companion to `../SKILL.md`. This file is loaded on demand when deeper examples or the
master cheat sheet are needed. It does not repeat the rules — it illustrates them with
extended examples drawn directly from this repository.

---

## Master Cheat Sheet

| Artifact | Convention | Example |
|---|---|---|
| PowerShell script | `Verb-Noun.ps1` | `Install-Packages.ps1` |
| PowerShell module | `Verb-Noun.psm1` | `Ensure-Winget.psm1` |
| YAML config file | `kebab-case.yml` | `winget-packages.yml` |
| DSC config file | `configuration.dsc.yaml` | `.configurations/Common/configuration.dsc.yaml` |
| Root documentation | `SCREAMING-KEBAB-CASE.md` | `README.md`, `CONTRIBUTING.md` |
| Skill file | `SKILL.md` (fixed name) | `agent-skills/documentation-and-naming/SKILL.md` |
| Skill reference file | `kebab-case.md` | `references/quick-reference.md` |
| Logical directory | `PascalCase` | `.configurations/Development/` |
| Parameter name | `PascalCase` | `$PackageId`, `$ConfigFile`, `$Force` |
| Local variable | `camelCase` | `$helperPath`, `$installArgs`, `$failedCount` |
| Script-scope constant | `$Script:PascalCase` | `$Script:DefaultTimeout` |
| Exported function | `Verb-Noun` (approved verb) | `Install-WingetPackage`, `Ensure-Winget` |
| Private function | `Verb-Noun` (not exported) | `Test-WingetFunctionality`, `Write-ProgressInfo` |
| Hashtable key | `PascalCase` | `PackageId`, `AlreadyInstalled`, `Success` |
| YAML app key | `snake_case` | `packages`, `cloud_infrastructure` |
| YAML DSC key | upstream schema verbatim | `allowPrerelease`, `directives`, `settings` |
| Section separator | `# ── Label ──────` to col 80 | `# ── Helpers ───────────────────────────────────────────────────────────────────` |
| Inline comment gap | two spaces before `#` | `$x = 1  # reason` |
| Script help — first line | `#Requires -Version 5.1` | before comment-based help block |

---

## Approved PowerShell Verbs Used in This Repository

The table below lists every verb currently in use and its accepted meaning within this
codebase. All new functions must use a verb from this list or another verb returned by
`Get-Verb`.

| Verb | Used For |
|---|---|
| `Install` | Installing software packages via winget |
| `Ensure` | Idempotent "verify it exists and is working; fix it if not" |
| `Enable` | Activating a Windows feature or service |
| `Test` | Returning `$true`/`$false` with no side-effects |
| `Get` | Retrieving a value with no side-effects |
| `Write` | Emitting output to a stream (host, verbose, warning, error) |
| `Read` | Parsing or consuming content from a file or stream |
| `Invoke` | Executing an action or external command |
| `Import` | Loading a module or data source into the current session |

---

## Extended File Naming Examples

### Naming a new helper module

Scenario: you are adding a module that validates whether a package ID is well-formed.

```
✅  helpers/Test-PackageId.psm1     — verb Test, noun PackageId, correct extension
✅  helpers/Get-PackageSource.psm1  — verb Get, specific noun

❌  helpers/validate-package.psm1   — kebab-case (reserved for YAML), missing PascalCase
❌  helpers/PackageHelper.psm1      — noun only, no verb
❌  helpers/Check-Package.psm1      — Check is not an approved verb; use Test-
```

### Naming a new YAML file

Scenario: you are adding a list of VS Code extensions to install.

```
✅  vscode-extensions.yml           — kebab-case, descriptive, .yml extension
✅  shell-profile-settings.yml      — multi-word kebab, clear purpose

❌  VSCodeExtensions.yml            — PascalCase (reserved for directories and PS)
❌  vscode_extensions.yml           — snake_case (reserved for YAML keys)
❌  extensions.yaml                 — too generic, .yaml not preferred
```

### Naming a new configuration subdirectory

Scenario: you are adding a configuration profile for a gaming setup.

```
✅  .configurations/Gaming/configuration.dsc.yaml
✅  .configurations/WorkFromHome/configuration.dsc.yaml

❌  .configurations/gaming/configuration.dsc.yaml     — lowercase directory
❌  .configurations/work-from-home/configuration.dsc.yaml  — kebab in directory
```

---

## Extended PowerShell Naming Examples

### Parameter block — real pattern from `Install-Packages.ps1`

```powershell
[CmdletBinding()]
param(
    # ✅ All PascalCase. Switch params have no type annotation (implied [switch]).
    # ✅ Optional string params default to empty or are left unbound (resolved in body).
    [string[]]$PackageList,
    [string]$ConfigFile,
    [switch]$Force,
    [switch]$Quiet
)
```

### Local variable naming — real pattern from `Install-Packages.ps1`

```powershell
# ✅ camelCase for every local
$helperPath            = Join-Path $PSScriptRoot 'helpers\Ensure-Winget.psm1'
$installArgs           = @('install', '--id', $PackageId, '--exact', '--silent')
$successCount          = 0
$alreadyInstalledCount = 0
$failedCount           = 0

# ✅ Loop variable is descriptive, not $i or $x
foreach ($package in $PackageList) { ... }

# ❌ Avoid these patterns
$HelperPath   = ...   # PascalCase — reader expects a parameter
$helper_path  = ...   # snake_case — inconsistent with rest of codebase
$hp           = ...   # cryptic abbreviation
```

### Full result hashtable — real pattern from `Install-Packages.ps1`

```powershell
# ✅ Initialise all keys before any branching. PascalCase keys. Typed defaults.
$result = @{
    PackageId        = $PackageId   # string  — echoes the input
    Success          = $false       # bool    — pessimistic default
    Message          = ''           # string  — empty until set
    AlreadyInstalled = $false       # bool    — pessimistic default
}

# Later in the function, set individual keys:
$result.Success          = $true
$result.AlreadyInstalled = $true
$result.Message          = 'Already installed'
return $result
```

### Export-ModuleMember — real pattern from `Ensure-Winget.psm1`

```powershell
# ✅ Only public functions are exported. Private helpers are omitted.
Export-ModuleMember -Function Ensure-Winget, Test-WingetFunctionality

# The function Test-WingetFunctionality is exported here because it is used
# by external callers. If it were purely internal, it would be omitted:
Export-ModuleMember -Function Ensure-Winget
```

---

## Extended PowerShell Documentation Examples

### Complete script help block — abridged from `Install-Packages.ps1`

```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    Installs a curated list of packages using Windows Package Manager (winget).

.DESCRIPTION
    This script ensures winget is available and functional, then installs packages
    defined in winget-packages.yml (located alongside this script). The YAML file
    is parsed without any external module dependency.

    A -PackageList override can be supplied on the command line to bypass the YAML
    file entirely, preserving backwards-compatible behaviour.

.PARAMETER PackageList
    Optional array of package IDs to install. If not specified the package list is
    loaded from winget-packages.yml in the same directory as this script.

.PARAMETER ConfigFile
    Path to the YAML packages file. Defaults to winget-packages.yml next to this
    script.

.PARAMETER Force
    Forces installation even if packages are already installed.

.PARAMETER Quiet
    Suppresses detailed output, only shows errors and final status.

.EXAMPLE
    .\Install-Packages.ps1
    Installs all packages defined in winget-packages.yml.

.EXAMPLE
    .\Install-Packages.ps1 -Force
    Forces (re)installation of all packages defined in winget-packages.yml.

.EXAMPLE
    .\Install-Packages.ps1 -PackageList @("Microsoft.PowerToys", "Git.Git")
    Installs only the specified packages (ignores winget-packages.yml).

.EXAMPLE
    .\Install-Packages.ps1 -ConfigFile "C:\custom\my-packages.yml"
    Installs packages from the specified YAML file.

.NOTES
    Requires administrator privileges.
    Compatible with Windows 10 1809+ and Windows 11.
#>
```

### Function help — minimum required for an exported function

```powershell
function Read-WingetPackagesYaml {
    <#
    .SYNOPSIS
        Parses a winget-packages.yml file and returns a flat array of package IDs.

    .PARAMETER Path
        Full path to the YAML file.

    .OUTPUTS
        [string[]]  Sorted array of winget package identifier strings.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    ...
}
```

### Function help — private helper (> 10 lines, help recommended)

```powershell
function Write-ProgressInfo {
    <#
    .SYNOPSIS
        Writes an informational message to the host in blue, unless -Quiet is set.
    #>
    param([string]$Message, [switch]$Quiet)
    if (-not $Quiet) { Write-Host $Message -ForegroundColor Blue }
}
```

### Section separator sizing

The separator comment fills to exactly column 80. Count the characters:

```
# ── Helpers ───────────────────────────────────────────────────────────────────
^                                                                               ^
col 1                                                                        col 80
```

Use this pattern for every major logical region in scripts longer than ~60 lines:

```powershell
# ── Helpers ───────────────────────────────────────────────────────────────────

function Write-ProgressInfo        { ... }
function Write-ProgressSuccess     { ... }
function Write-ProgressWarning     { ... }

# ── Lightweight YAML parser ───────────────────────────────────────────────────

function Read-WingetPackagesYaml   { ... }

# ── Package installer ─────────────────────────────────────────────────────────

function Install-WingetPackage     { ... }

# ── Main ──────────────────────────────────────────────────────────────────────

Write-Host '=== Package Installation Script ===' -ForegroundColor Cyan
```

---

## Extended YAML Documentation Examples

### Complete file header — from `winget-packages.yml`

```yaml
# winget-packages.yml
# Curated list of packages to install via Windows Package Manager (winget).
# All categories are merged at install time — grouping is purely for organisation.
#
# Usage:
#   .\Install-Packages.ps1                           # installs everything defined here
#   .\Install-Packages.ps1 -Force                    # force-reinstall all packages
#   .\Install-Packages.ps1 -PackageList @("Git.Git") # override list
#   .\Install-Packages.ps1 -ConfigFile ".\custom.yml" # use a different file
```

### Section comment alignment

The `# ──` separator is indented to match the block it labels. In a top-level mapping
it sits at column 3 (two-space indent + `#`); inside a nested mapping it indents further.

```yaml
packages:

  # ── Development tools & languages ────────────────────────────────────────────
  development:
    - Git.Git                                   # Git version control
    - GitHub.cli                                # GitHub CLI (gh)

  # ── Cloud & infrastructure ────────────────────────────────────────────────────
  cloud_infrastructure:
    - Amazon.AWSCLI                             # AWS CLI v2
    - Hashicorp.Terraform                       # Terraform IaC
```

### DSC YAML — upstream schema keys are not recased

```yaml
# ✅ DSC keys follow the Microsoft WinGet DSC schema verbatim
- resource: Microsoft.WinGet.DSC/WinGetPackage
  directives:
    description: Terraform
    allowPrerelease: true
  settings:
    id: Hashicorp.Terraform
    source: winget

# ❌ Do not recase DSC keys to match application YAML conventions
- resource: Microsoft.WinGet.DSC/WinGetPackage
  Directives:          # wrong — schema key is lowercase
    Description: Terraform
    allow_prerelease: true   # wrong — schema key is camelCase
```

---

## Skill Versioning Reference

Skill file versions follow Semantic Versioning (`MAJOR.MINOR.PATCH`). Update the
`metadata.version` field in `SKILL.md` on every change.

| Type of change | Bump | Example |
|---|---|---|
| Removes or inverts an existing rule | `MAJOR` | `1.0.0` → `2.0.0` |
| Adds a new rule or section | `MINOR` | `1.0.0` → `1.1.0` |
| Clarification, typo fix, new example | `PATCH` | `1.0.0` → `1.0.1` |

---

## Common Mistakes and Corrections

| Mistake | Why it's wrong | Correction |
|---|---|---|
| `helpers/validate-package.psm1` | kebab-case in a PowerShell file name | `helpers/Test-PackageId.psm1` |
| `function Check-Winget` | `Check` is not an approved verb | `function Test-Winget` |
| `$PackagePath = ...` inside a function body | PascalCase local looks like a parameter | `$packagePath = ...` |
| `[string]$force` parameter | Parameter is lowercase | `[switch]$Force` |
| Comment: `# Loop through packages` above `foreach` | States the obvious | Remove it, or explain *why* the loop exists |
| YAML key `cloudInfrastructure:` | camelCase — use snake_case for app YAML | `cloud_infrastructure:` |
| Missing `#Requires` on a new `.ps1` | Every script must declare its minimum version | Add `#Requires -Version 5.1` on line 1 |
| `.EXAMPLE` block with no explanation line | The second line of an example explains what it does | Add a sentence after the command |
| End-of-line comment with single space: `$x = 1 # note` | Convention requires two spaces | `$x = 1  # note` |