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
2. **`New-WingetConfiguration.ps1`** reads that YAML and emits a fully‑formed DSC configuration file. This bridges the gap between a simple, human‑friendly list and the verbose DSC format that `winget configure` expects.
3. **`winget configure`** walks the generated DSC file and ensures every listed package is present. The `Microsoft.WinGet.DSC/WinGetPackage` resource defaults to `ensure: Present`, so the operation is declarative and idempotent — it only installs what is missing.

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

You have two options:

| Approach | Steps |
|----------|-------|
| **Remove from list** | Delete the entry from `winget-packages.yml`, re‑run the generator, then re‑apply. The package stays installed but is no longer managed. |
| **Uninstall via DSC** | Edit `.configurations\configuration.dsc.yaml` directly and change `ensure: Present` to `ensure: Absent` for the target package, then re‑apply. `winget configure` will uninstall it. |

> **Tip:** `.configurations\configuration.dsc.yaml` is a generated artifact. Any hand‑edits will be overwritten the next time you run the generator. If you need a permanent removal, delete the package from `winget-packages.yml` and use `winget uninstall` for the one‑time cleanup.

## File Reference

| File | Purpose |
|------|---------|
| `winget-packages.yml` | Single source of truth for package IDs, organised by category. |
| `New-WingetConfiguration.ps1` | Generator script — reads YAML, emits `.configurations\configuration.dsc.yaml`. |
| `Install-Packages.ps1` | Legacy imperative installer — calls `winget install` per package. Kept for local accounts. |
| `.configurations\configuration.dsc.yaml` | **Generated** DSC file consumed by `winget configure`. Schema version [0.2](https://aka.ms/configuration-dsc-schema/0.2). |
| `helpers\Enable-Winget.psm1` | Helper module to enable the winget feature. |
| `helpers\Ensure-Winget.psm1` | Helper module to ensure winget is installed and available. |
| `helpers\Test-WingetEnabled.psm1` | Helper module to test whether winget is enabled. |

## Prerequisites

- **OS:** Windows 10 version 1809+ or Windows 11
- **PowerShell:** 7.6 or later
- **winget:** Windows Package Manager (`winget --version` to verify)
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