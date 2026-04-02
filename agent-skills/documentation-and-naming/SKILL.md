---
name: documentation-and-naming
description: Apply naming conventions and documentation standards for all file types in this repository. Use when creating, editing, or reviewing PowerShell scripts, PowerShell modules, YAML configuration files, or Markdown documents. Covers file names, directory names, parameter and variable casing, function naming, comment-based help blocks, inline comments, section separators, and YAML header comments.
license: MIT
compatibility: Applies to the winget-configure repository. Governs *.ps1, *.psm1, *.yml, *.yaml, and *.md files. No runtime or tooling dependency — rules are enforced through code review and agent-assisted editing.
metadata:
  author: daveyb
  version: "1.0.0"
---

# Documentation and Naming Standards

Standards for every file type in this repository. Apply these rules when creating or
modifying any file. When a rule conflicts with an upstream schema (e.g. DSC YAML keys),
the upstream schema wins.

Read `references/quick-reference.md` for a single-table cheat sheet of every rule.

---

## 1. File Naming

### PowerShell Scripts (`.ps1`) and Modules (`.psm1`)

Use `Verb-Noun` in PascalCase. The verb must be on the PowerShell approved verb list
(run `Get-Verb` to check). The noun must be specific and unambiguous.

```
✅  Install-Packages.ps1
✅  Ensure-Winget.psm1
✅  Test-WingetEnabled.psm1

❌  install_packages.ps1   (snake_case)
❌  installPackages.ps1    (camelCase)
❌  packages.ps1           (missing verb)
❌  Do-Stuff.ps1           (unapproved verb)
```

### YAML Files (`.yml` / `.yaml`)

Use `kebab-case`. Prefer `.yml` over `.yaml` for consistency. DSC configuration files
are the sole exception — they follow the established `configuration.dsc.yaml` convention
inside their named subdirectory.

```
✅  winget-packages.yml
✅  .configurations/Common/configuration.dsc.yaml   (DSC exception)

❌  WingetPackages.yml
❌  winget_packages.yml
```

### Markdown Files (`.md`)

`README.md` is always uppercase. Standalone documentation files use
`SCREAMING-KEBAB-CASE.md`. Skill files under `agent-skills/` use `kebab-case.md`.

```
✅  README.md
✅  CONTRIBUTING.md
✅  agent-skills/documentation-and-naming/SKILL.md
```

### Directories

Use PascalCase for logical grouping directories.

```
✅  .configurations/Common/
✅  .configurations/Development/
✅  helpers/

❌  .configurations/common/
❌  helper_scripts/
```

---

## 2. PowerShell Naming

### Parameters

PascalCase. Mirror the casing of standard PowerShell parameters (`-Path`, `-Force`,
`-Quiet`, `-ErrorAction`).

```powershell
# ✅
param(
    [string]$PackageId,
    [string]$ConfigFile,
    [switch]$Force,
    [switch]$Quiet
)

# ❌
param([string]$packageId, [string]$config_file, [switch]$force)
```

### Local Variables

camelCase for all function-scoped variables.

```powershell
# ✅
$helperPath           = Join-Path $PSScriptRoot 'helpers\Ensure-Winget.psm1'
$alreadyInstalledCount = 0

# ❌
$HelperPath           = ...   (PascalCase — reserved for parameters)
$helper_path          = ...   (snake_case)
```

### Functions

All functions use `Verb-Noun`. Exported (public) functions are declared in
`Export-ModuleMember`. Private helpers are not exported but still follow the convention.

```powershell
# ✅ exported
function Install-WingetPackage     { ... }
function Ensure-Winget             { ... }
function Read-WingetPackagesYaml   { ... }

# ✅ private — not in Export-ModuleMember
function Test-WingetFunctionality  { ... }
function Write-ProgressInfo        { ... }

# ❌
function installPackage  { ... }   (camelCase)
function Helper          { ... }   (no verb)
```

### Result Hashtables

Functions that return structured data use a hashtable with PascalCase keys, initialised
with all keys before any branching logic.

```powershell
# ✅
$result = @{
    PackageId        = $PackageId
    Success          = $false
    Message          = ''
    AlreadyInstalled = $false
}
```

---

## 3. PowerShell Documentation

### Script-Level Comment-Based Help

Every `.ps1` file must open with a comment-based help block **before** `param()`.
`#Requires` statements go on line 1, before the help block.

Required sections: `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER` (one per param),
`.EXAMPLE` (at least one), `.NOTES`.

```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    One-line description of what the script does.

.DESCRIPTION
    Extended description. Explain the approach, not just the outcome.
    Mention non-obvious dependencies or side-effects.

.PARAMETER ParameterName
    What this parameter controls. State the default behaviour when omitted.

.EXAMPLE
    .\Script-Name.ps1
    What the plain invocation does.

.EXAMPLE
    .\Script-Name.ps1 -Force -Quiet
    What this variant does and when to use it.

.NOTES
    Prerequisites: admin rights, OS version, external tools.
#>
```

### Function-Level Comment-Based Help

Every exported function requires comment-based help. Private helpers with more than
~10 lines of logic should also have it.

Required: `.SYNOPSIS`. Add `.PARAMETER`, `.OUTPUTS`, and `.EXAMPLE` when they add
meaningful information.

```powershell
function Install-WingetPackage {
    <#
    .SYNOPSIS
        Installs a single package using winget.

    .PARAMETER PackageId
        The exact winget package identifier (e.g. "Git.Git").

    .PARAMETER Force
        Forces installation even if the package is already installed.

    .OUTPUTS
        [hashtable]  Keys: PackageId, Success, Message, AlreadyInstalled.
    #>
    [CmdletBinding()]
    param(...)
}
```

### Inline Comments

- Comment **why**, not what. The code explains what.
- Own-line comments are indented to match the code they describe.
- End-of-line comments use two spaces before `#`.
- Always comment non-obvious exit codes and magic numbers.

```powershell
# ✅ — explains why
# winget exit code -1978335189 means the package is already at the target version.
elseif ($LASTEXITCODE -eq -1978335189) {

# ✅ — end-of-line with two-space gap
$installArgs += '--force'  # required when downgrading a pinned version

# ❌ — states the obvious
# Loop through packages
foreach ($package in $PackageList) {
```

### Section Separators

Divide long scripts into named regions with the `# ── Label ───` separator style.
Trailing dashes fill to column 80.

```powershell
# ── Helpers ───────────────────────────────────────────────────────────────────

# ── Lightweight YAML parser ───────────────────────────────────────────────────

# ── Main ──────────────────────────────────────────────────────────────────────
```

---

## 4. YAML Documentation

### File Header Comment

Every hand-authored `.yml` / `.yaml` file opens with a comment block containing:
1. The file name.
2. One-sentence purpose.
3. How the file is consumed (what reads it and how).
4. A `Usage:` block with example invocations where applicable.

```yaml
# winget-packages.yml
# Curated list of packages to install via Windows Package Manager (winget).
# All categories are merged at install time — grouping is purely for organisation.
#
# Usage:
#   .\Install-Packages.ps1                           # installs everything defined here
#   .\Install-Packages.ps1 -Force                    # force-reinstall all packages
#   .\Install-Packages.ps1 -PackageList @("Git.Git") # override list
```

### Section Comments

Use the `# ── Section name ───` separator style, indented to match the block it precedes.

```yaml
packages:

  # ── Development tools & languages ────────────────────────────────────────────
  development:
    - Git.Git

  # ── Cloud & infrastructure ───────────────────────────────────────────────────
  cloud_infrastructure:
    - Amazon.AWSCLI
```

### Inline Comments

Two spaces before `#`. One clause. Short.

```yaml
# ✅
    - Terraform-docs.Terraform-docs             # terraform-docs
    - Microsoft.FoundryLocal                    # Azure AI Foundry Local

# ❌ — no space gap
    - Microsoft.FoundryLocal# Azure AI Foundry Local
```

### YAML Key Casing

- Application YAML top-level keys: `snake_case`
- DSC resource keys: follow the upstream schema verbatim (`resource`, `directives`,
  `settings`, `allowPrerelease`, etc.)

---

## 5. Markdown Documentation

### README.md Structure

Required sections, in order:

1. H1 title (repository or component name)
2. Overview — one to three sentences
3. Usage — concrete examples in fenced, language-tagged code blocks
4. Prerequisites — OS version, privilege requirements, external tools
5. Troubleshooting — the three to five most common failure modes with remediation
6. Resources — links to upstream documentation

### Code Blocks

Always specify the language for syntax highlighting.

````markdown
```powershell
.\Install-Packages.ps1 -Force
```

```yaml
packages:
  development:
    - Git.Git
```
````

### Tables

Use tables for option comparisons or multi-attribute item lists. Align pipes in source.

```markdown
| Factor           | Mode 1 (PowerShell) | Mode 2 (WinGet Configure) |
|------------------|---------------------|---------------------------|
| Account Type     | Local accounts ✅    | Microsoft accounts only   |
| Microsoft Store  | Not required ✅      | Required                  |
```
