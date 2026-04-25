# Windows Package Manager Configuration

Declarative, idempotent Windows package management powered by [winget configure](https://learn.microsoft.com/windows/package-manager/configuration/) and DSC. Maintain a single package list, generate a DSC configuration, and apply it in one command.

## Quick Start

```powershell
# 1. Edit the package list (optional — sensible defaults are included)
notepad .\winget-packages.yml

# 2. Generate the DSC configuration file
.\New-WingetConfiguration.ps1

# 3. Apply it (idempotent — already-installed packages are skipped)
winget configure -f .configurations\configuration.dsc.yaml
```

> **Note:** `winget configure` requires a Microsoft-connected account. If you are using a local Windows account, see [Legacy Mode](#legacy-mode) below.

## How It Works

```
winget-packages.yml          ← you edit this (single source of truth)
        │
        ▼
New-WingetConfiguration.ps1  ← generator script
        │
        ▼
.configurations/
  configuration.dsc.yaml     ← generated DSC artifact (schema 0.2)
        │
        ▼
winget configure              ← applies desired state to your machine
```

1. **`winget-packages.yml`** is the single source of truth. Packages are grouped by category purely for organisation — all categories are merged at generation time.
2. **`New-WingetConfiguration.ps1`** reads that YAML, compares it against the previously committed version in Git (`HEAD`), and emits a fully‑formed DSC configuration file. Newly added packages get `ensure: Present`; packages you remove from the YAML are automatically marked `ensure: Absent` so that `winget configure` will uninstall them.
3. **`winget configure`** walks the generated DSC file and reconciles each resource. Packages marked `Present` are installed if missing; packages marked `Absent` are uninstalled if found. The operation is declarative and idempotent.

## Editing the Package List

Open `winget-packages.yml` and add, remove, or reorganise entries under any category:

```yaml
packages:
  development:
    - Git.Git
    - GitHub.cli
  browsers:
    - eloston.ungoogled-chromium
```

After saving your changes, regenerate and apply:

```powershell
.\New-WingetConfiguration.ps1
winget configure -f .configurations\configuration.dsc.yaml
```

### Removing a Package

Simply delete the entry from `winget-packages.yml`, then regenerate and apply:

```powershell
.\New-WingetConfiguration.ps1 -Force
winget configure -f .configurations\configuration.dsc.yaml
```

The generator compares your working‑tree YAML against the last committed version (`git show HEAD:winget-packages.yml`). Removed packages follow a two‑commit lifecycle:

| Commit | What happens |
|--------|-------------|
| **1st** (you remove the package) | The generator emits the resource with `ensure: Absent`. Running `winget configure` uninstalls it. |
| **2nd** (the removal is already in HEAD) | The `Absent` tombstone is no longer in the previous YAML either, so the generator prunes the resource entirely from the DSC file. |

This means you never need to hand‑edit the DSC file — just add or remove lines in `winget-packages.yml` and let the generator handle the rest.

> **Note:** Git must be installed and on your `PATH` for removal tracking to work. If Git is unavailable the generator still works, but removed packages will simply disappear from the DSC file without an `Absent` tombstone (you would need to run `winget uninstall` manually).

## File Reference

| File | Purpose |
|------|---------|
| `winget-packages.yml` | Single source of truth for package IDs, organised by category. |
| `New-WingetConfiguration.ps1` | Generator script — reads YAML, diffs against Git HEAD, emits `.configurations\configuration.dsc.yaml` with removal tracking. |
| `Install-Packages.ps1` | Legacy imperative installer — calls `winget install` per package. Kept for local accounts. |
| `.configurations\configuration.dsc.yaml` | **Generated** DSC file consumed by `winget configure`. Schema version [0.2](https://aka.ms/configuration-dsc-schema/0.2). |
| `helpers\Enable-Winget.psm1` | Helper module to enable the winget feature. |
| `helpers\Ensure-Winget.psm1` | Helper module to ensure winget is installed and available. |
| `helpers\Test-WingetEnabled.psm1` | Helper module to test whether winget is enabled. |

## Prerequisites

- **OS:** Windows 10 version 1809+ or Windows 11
- **PowerShell:** 7.6 or later
- **winget:** Windows Package Manager (`winget --version` to verify)
- **Git:** Required for automatic removal tracking (`git --version` to verify)
- **Privileges:** Administrator (elevated) PowerShell session
- **Account:** Microsoft-connected account (for `winget configure` only)

### Execution Policy

If you have not already done so, allow locally‑created scripts to run:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| **`winget` not found** | The `helpers/` modules can bootstrap winget for you. Import `Ensure-Winget.psm1` and run its exported function. |
| **Microsoft Store / account errors with `winget configure`** | This command requires a Microsoft‑connected account. Switch to [Legacy Mode](#legacy-mode) if you are on a local account. |
| **Package ID not found** | IDs change over time. Search the [winget-pkgs repository](https://github.com/microsoft/winget-pkgs) for the current ID. |
| **Permission denied** | Right‑click PowerShell → **Run as Administrator**, then retry. |
| **DSC file looks stale** | Re‑run `.\New-WingetConfiguration.ps1` after editing `winget-packages.yml`. The DSC file is a generated artifact. |

## Legacy Mode

`Install-Packages.ps1` is an imperative PowerShell installer kept as a fallback for **local (non‑Microsoft) Windows accounts** that cannot use `winget configure`.

```powershell
# Install everything defined in winget-packages.yml
.\Install-Packages.ps1

# Force reinstall all packages
.\Install-Packages.ps1 -Force

# Install a specific subset
.\Install-Packages.ps1 -PackageList @("Git.Git", "GitHub.cli")
```

Key differences from the recommended workflow:

- Reads `winget-packages.yml` directly — no DSC generation step.
- Calls `winget install` for each package sequentially.
- **Not idempotent** — may attempt to reinstall already‑present packages.
- Does **not** require a Microsoft‑connected account.

## Contributing

Contributions are welcome. Feel free to open issues or submit pull requests for new packages, script improvements, or documentation updates.

## License

This repository is provided as‑is under the [MIT License](https://opensource.org/licenses/MIT) for personal and professional use.

## Resources

- [Windows Package Manager Documentation](https://learn.microsoft.com/windows/package-manager/)
- [WinGet CLI Reference](https://learn.microsoft.com/windows/package-manager/winget/)
- [DSC Configuration Reference](https://learn.microsoft.com/windows/package-manager/configuration/)
- [DSC Schema 0.2](https://aka.ms/configuration-dsc-schema/0.2)
- [WinGet Packages Repository](https://github.com/microsoft/winget-pkgs)