# Windows Package Manager Configuration

Declarative, idempotent Windows package management powered by [winget configure](https://learn.microsoft.com/windows/package-manager/configuration/) and DSC. Maintain a single package list, generate a DSC configuration, and apply it in one command.

## Quick Start

```powershell
# 1. Edit the package list (optional — sensible defaults are included)
edit .\winget-packages.yml

# 2. Generate the DSC configuration file
.\New-WingetConfiguration.ps1

# 3. Apply it (idempotent — already-installed packages are skipped)
winget configure -f .configurations\configuration.dsc.yaml
```

> **Note:** Run step 3 from a normal PowerShell window. When `Chrome.LockScreenPlayback` runs, approve the [administrator prompt](#elevated-session). `winget configure` also requires a Microsoft-connected account. If you are using a local Windows account, see [Legacy Mode](#legacy-mode) below.

## Apply the Released Configuration Without Cloning

Each [GitHub release](https://github.com/daveyb/winget-configure/releases/latest) ships `configuration.dsc.yaml` as a downloadable asset. If you want to apply the exact package set without cloning the repository, download and run it directly from PowerShell:

```powershell
# Download the latest released configuration
$dest = Join-Path $env:TEMP "configuration.dsc.yaml"
Invoke-WebRequest `
    -Uri "https://github.com/daveyb/winget-configure/releases/latest/download/configuration.dsc.yaml" `
    -OutFile $dest

# Apply it
winget configure -f $dest
```

Or as a single pipeline:

```powershell
winget configure -f ($(Invoke-WebRequest `
    "https://github.com/daveyb/winget-configure/releases/latest/download/configuration.dsc.yaml" `
    -OutFile ($d = Join-Path $env:TEMP "configuration.dsc.yaml")) ; $d)
```

To target a specific version instead of the latest, replace `latest/download` with `download/<tag>` — for example:

```powershell
# Pin to a specific release tag
Invoke-WebRequest `
    -Uri "https://github.com/daveyb/winget-configure/releases/download/v1.1.1/configuration.dsc.yaml" `
    -OutFile (Join-Path $env:TEMP "configuration.dsc.yaml")
```

> **Prerequisites still apply:** run it from a normal PowerShell window and approve the [administrator prompt](#elevated-session) for the lock-screen resource. `winget configure` also requires a Microsoft-connected account. See [Prerequisites](#prerequisites).

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

## Updating Installed Packages

Use `Update-Packages.ps1` instead of `winget upgrade --all`. WSL's winget MSIX installer fails with `0x80073d28` when administrator privileges are required; this script pins `Microsoft.WSL` so winget skips it, upgrades everything else, then runs `wsl --update --web-download`.

```powershell
.\Update-Packages.ps1
```

`winget configure` bootstraps WSL with a `PSDscResources/Script` resource (`Microsoft.WSL.WebUpdate`) instead of `WinGetPackage`, so a MSIX `0x80073d28` cannot stop the run. Test is local (a real `wsl --version` `WSL version:` line plus a blocking `Microsoft.WSL` pin) so inbox stubs do not count and later configures do not restart WSL. When that version is missing, Set runs `wsl --update --web-download` (same path as `Update-Wsl`) and pins; if WSL is already installed, Set only adds the pin. Keep WSL current after that with `Update-Packages.ps1`. After the pin is in place, a raw `winget upgrade --all` will no longer try (and fail) to upgrade WSL.

## Lock-screen playback

Pocket Casts on Windows is the Chrome app. Chrome suspends a window it decides is covered, including while the screen is locked, and the episode pauses. The generated configuration includes a `Chrome.LockScreenPlayback` script resource after the package resources. It:

- sets Chrome machine policy `HKLM\SOFTWARE\Policies\Google\Chrome\WindowOcclusionEnabled` to `0`
- resets the console lock display-off timeout (`VIDEOCONLOCK`) to 30 seconds on AC and on battery

The policy applies to every user and every Chrome window, and this script does not remove it later.

Run `winget configure` from a normal PowerShell window. When it reaches `Chrome.LockScreenPlayback`, Windows shows a User Account Control prompt. Approve it. That prompt writes the Chrome policy and the 30-second timeout. Dismissing it fails only that resource:

`Lock-screen playback settings require an elevated PowerShell session. Approve the administrator prompt.`

The resource is after the package resources, so that failure does not undo packages that already applied. Do not start this command from an Administrator window. An elevated `winget configure` process fails `WinGetPackage` with "Failed to create instance." `Install-Packages.ps1` shows the same prompt. If that script is not able to elevate, it warns and still installs packages.

```powershell
winget configure -f .configurations\configuration.dsc.yaml
```

Or, for a local account:

```powershell
.\Install-Packages.ps1
```

Approve the prompt when it appears. The PowerShell window itself stays a normal window. Do not add `securityContext: elevated` to this resource. WinGet then fails every unit with "The file name is too long."

Quit Chrome completely and open it again before the next listen. Chrome will show "Managed by your organization" because of this policy. Closing the lid, pressing the power button, or choosing Sleep still stops audio.

## Shell profile

`winget configure` writes the PowerShell 7 profile, installs Terminal-Icons, installs Departure Mono, and sets that font on every Windows Terminal profile. PowerShell is the first profile in the list, and new tabs open it.

The profile file is the PowerShell 7 `$PROFILE`. The usual path is `Documents\PowerShell\Microsoft.PowerShell_profile.ps1`. The file is replaced with this text.

```powershell
oh-my-posh --init --shell pwsh --config https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/refs/heads/main/themes/marcduiker.omp.json | Invoke-Expression

# Install-Module -Name Terminal-Icons -Repository PSGallery
Import-Module -Name Terminal-Icons
```

`JanDeDobbeleer.OhMyPosh` is already installed by winget. Terminal-Icons comes from PSGallery for the current user. The install marks the PSGallery repository Trusted for the current user.

The font files come from the Nerd Fonts 3.5.1 Departure Mono zip. They are registered in the current user's Fonts folder, not in `C:\Windows\Fonts`. The Windows Terminal face is `DepartureMono Nerd Font`. `profiles.defaults.font.face` is set to that name. Font settings on individual profiles are removed so the default face applies to every profile.

PowerShell is the profile named `PowerShell` from `Windows.Terminal.PowershellCore`. It is moved to the start of `profiles.list`. `defaultProfile` is set to that profile's guid. Windows PowerShell stays in the list after it. Comments already in `settings.json` are kept. The file is rewritten, so spacing can change. The intended edits are the default font, per-profile font keys, list order, and `defaultProfile`.

`winget configure` can run that script as a script block under Windows PowerShell 5.1. The block has no path, so the resource writes it to a temp file and relaunches it with pwsh before Test, Set, or Get.

`Install-Packages.ps1` runs these steps after the package loop. If the step fails, the script warns and package installation still finishes. Open a new Windows Terminal tab to see the prompt and the font.

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
| `Install-Packages.ps1` | Legacy imperative installer — calls `winget install` per package. Kept for local accounts. Skips winget for `Microsoft.WSL` and calls `Update-Wsl` (`wsl --update --web-download`) so a blocking pin cannot fail the run. |
| `Update-Packages.ps1` | Upgrade wrapper — pins `Microsoft.WSL`, runs `winget upgrade --all`, then updates WSL via web-download. |
| `.configurations\configuration.dsc.yaml` | **Generated** DSC file consumed by `winget configure`. Schema version [0.2](https://aka.ms/configuration-dsc-schema/0.2). |
| `helpers\Enable-Winget.psm1` | Helper module to enable the winget feature. |
| `helpers\Ensure-Winget.psm1` | Helper module to ensure winget is installed and available. |
| `helpers\Test-WingetEnabled.psm1` | Helper module to test whether winget is enabled. |
| `helpers\Update-Wsl.psm1` | Helper module to update WSL via web-download and pin `Microsoft.WSL`. |
| `helpers\LockScreenPlayback.ps1` | Desired state for Chrome lock-screen playback and the 30-second console lock display timeout. |
| `helpers\ShellProfile.ps1` | Desired state for the PowerShell 7 profile, Terminal-Icons, Departure Mono, and the Windows Terminal profile list. |

## Prerequisites

- **OS:** Windows 10 version 1809+ or Windows 11
- **PowerShell:** 7.6 or later
- **winget:** Windows Package Manager (`winget --version` to verify)
- **Git:** Required for automatic removal tracking (`git --version` to verify)
- **Privileges:** Approve the administrator prompt for the lock-screen resource. See [Elevated session](#elevated-session).
- **Account:** Microsoft-connected account (for `winget configure` only)

### Elevated session

Lock-screen playback writes `HKLM\SOFTWARE\Policies\Google\Chrome` and resets the active power scheme's console lock display timeout to 30 seconds. Run `winget configure` from a normal PowerShell window:

```powershell
Set-Location .\winget-configure
winget configure -f .configurations\configuration.dsc.yaml
```

Use the path of your clone in `Set-Location`. When `Chrome.LockScreenPlayback` runs, approve the User Account Control prompt. That prompt is the elevation. Leave the original window as a normal window. Starting the whole command with **Run as administrator** makes package configuration fail with "Failed to create instance." Dismissing the lock-screen prompt skips the Chrome policy and the 30-second timeout. Package installation still continues.

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
| **Lock-screen playback settings require an elevated PowerShell session** | Run `winget configure` again from a normal window and approve the [administrator prompt](#elevated-session). |
| **Failed to create instance** on every `WinGetPackage` | The command was started as Administrator. Run it again from a normal PowerShell window and approve the lock-screen prompt. |
| **The file name is too long**, or **-2147024785** / **0x8007006F**, on every `WinGetPackage` | The configuration was marked `securityContext: elevated`. Use the current `.configurations\configuration.dsc.yaml` from a normal PowerShell window. |
| **DSC file looks stale** | Re‑run `.\New-WingetConfiguration.ps1` after editing `winget-packages.yml`. The DSC file is a generated artifact. |
| **`Microsoft.WSL` upgrade fails with `0x80073d28`** | Do not retry `winget upgrade Microsoft.WSL`. Run `.\Update-Packages.ps1` (or `wsl --update --web-download`). The configuration pins WSL so `winget upgrade --all` skips it. |

## Legacy Mode

`Install-Packages.ps1` is an imperative PowerShell installer kept as a fallback for **local (non‑Microsoft) Windows accounts** that cannot use `winget configure`. Run it from a normal PowerShell window. It shows the same [administrator prompt](#elevated-session) for the lock-screen settings. If that prompt is dismissed, package installation continues.

```powershell
# Install everything defined in winget-packages.yml
.\Install-Packages.ps1

# Force reinstall all packages
.\Install-Packages.ps1 -Force

# Install a specific subset
.\Install-Packages.ps1 -PackageList @("Git.Git", "GitHub.cli")

# Uninstall ALL managed packages (destructive — removes every package in winget-packages.yml)
.\Install-Packages.ps1 -Thermonuclear
```

> **Warning:** `-Thermonuclear` calls `winget uninstall` on every package in `winget-packages.yml`. There is no confirmation prompt — it will uninstall everything immediately.

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
