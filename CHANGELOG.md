# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-10-04

### Added
- `Shell.Profile` writes the PowerShell 7 `$PROFILE` with the oh-my-posh marcduiker init and `Import-Module Terminal-Icons`. The profile file is replaced with that text.
- Terminal-Icons is installed from PSGallery for the current user. `JanDeDobbeleer.OhMyPosh` stays a winget package.
- Departure Mono Nerd Font 3.5.1 is downloaded from the pinned Nerd Fonts zip and registered in the per-user Fonts folder. Windows Terminal `profiles.defaults` uses the face `DepartureMono Nerd Font`. Font settings on individual profiles are removed so every profile uses that face.
- The Windows Terminal profile list puts PowerShell first, and `defaultProfile` opens that profile. Windows PowerShell stays later in the list.
- `Install-Packages.ps1` applies the same steps after the package loop. If that step fails, the script warns and package installation continues.

### Fixed
- `Shell.Profile` reads its script path only when that property exists. `winget configure` runs the test script as a script block under StrictMode, and `MyCommand.Path` threw `PropertyNotFoundException` before the unit could test the profile.
- Windows PowerShell 5.1 still has no path for that script block. Test, Set, and Get write the script to a temp file and relaunch it with pwsh. They no longer throw because `MyCommand.Path` and `PSCommandPath` are empty.
- Windows Terminal `settings.json` comments are kept. The edit sets the default font, removes per-profile font keys, puts PowerShell first, and sets `defaultProfile`. The file is rewritten, so spacing can change. It does not rewrite the file through `System.Text.Json` and drop every comment.
- Profile name, command line, source, and guid are read with `GetValue<string>()` via reflection. `JsonNode.ToString()` returns JSON text, so a quoted name was not a match and a second PowerShell profile could be inserted. The call is not written as `GetValue[string]()`, which Windows PowerShell 5.1 cannot parse, so the 5.1 relaunch can still start.
- `Shell.Profile` depends on `Microsoft.PowerShell`, `Microsoft.WindowsTerminal`, and `JanDeDobbeleer.OhMyPosh`. It does not run until those packages are present. `Install-Packages.ps1` skips the same step unless those three succeeded.
- Terminal-Icons still installs from PSGallery for the current user only. That install marks PSGallery Trusted for the call, then restores the previous InstallationPolicy. It does not leave a permanent current-user trust policy. `Uninstall-Module -Name Terminal-Icons -Scope CurrentUser` removes the module.

## [1.1.21] - 2026-10-03

### Fixed
- `winget configure` no longer marks `Chrome.LockScreenPlayback` with `securityContext: elevated`. That directive made every unit fail with `0x8007006F` (`-2147024785`), "The file name is too long."
- The lock-screen resource shows its own User Account Control prompt and applies the Chrome policy and the 30-second timeout from that elevated process. Run `winget configure` from a normal PowerShell window and approve the prompt. Running the whole command as Administrator makes `WinGetPackage` fail with "Failed to create instance."
- That prompt treats the result file as the only success signal. It keeps polling until that file is non-empty or ten minutes pass. A RunAs handle exit is not completion and is not failure, and the worker directory is not deleted until that write is observed or the deadline passes. A missing or inaccessible process exit code does not fail a completed apply. The script and result paths are quoted so a TEMP directory that contains spaces still starts. `winget configure` hosts the script outside `powershell.exe`, so that prompt starts Windows PowerShell. A PowerShell 7 window starts PowerShell 7.

## [1.1.20] - 2026-10-03

### Fixed
- `Chrome.LockScreenPlayback` declares `securityContext: elevated`. `winget configure` requests administrator approval for the Chrome policy and the 30-second lock-screen timeout when the window is not already elevated. Approve that prompt. `Install-Packages.ps1` still has to be started from an Administrator PowerShell window.

## [1.1.19] - 2026-10-03

### Fixed
- Pocket Casts lock-screen playback resets the console lock display-off timeout (`VIDEOCONLOCK`) to 30 seconds on AC and battery, and sets Chrome machine policy `WindowOcclusionEnabled` to 0. Run `winget configure` or `Install-Packages.ps1` from an Administrator PowerShell window. If that window is not elevated, `Install-Packages.ps1` warns and package installation continues. Restart Chrome before the next locked-screen listen.

## [1.1.18] - 2026-10-03

### Fixed
- Pocket Casts pauses when the screen locks because Chrome treats the lock screen as a covered window. `winget configure` sets Chrome machine policy `WindowOcclusionEnabled` to 0. It does not change the console lock display-off timeout (`VIDEOCONLOCK`); that value is not part of compliance. The timeout reader parses only the block after the VIDEOCONLOCK alias or GUID, and a missing block includes powercfg stdout in the error.
- `Install-Packages.ps1` applies the same Chrome policy. Run it from an Administrator PowerShell window. If that step fails, it warns and package installation continues. The DSC resource is after the package resources, so a lock-screen failure does not abort them. Restart Chrome before the next locked-screen listen. Closing the lid, the power button, and Sleep still stop audio.

## [1.1.17] - 2026-09-05

### Added
- `Update-Packages.ps1` to run `winget upgrade --all` and then update WSL via `wsl --update --web-download`
- `helpers/Update-Wsl.psm1` to pin `Microsoft.WSL` and keep WSL current without the winget MSIX installer

### Fixed
- `Microsoft.WSL` upgrades no longer depend on `winget upgrade`, which fails with `0x80073d28` when administrator privileges are required
- DSC `TestScript` for WSL is local-only: a real `wsl --version` `WSL version:` line plus a blocking `Microsoft.WSL` pin. Inbox `System32\wsl.exe` stubs do not count. It no longer calls `api.github.com`. Later `winget configure` runs therefore do not restart WSL.
- When Test fails because that version is missing, `SetScript` runs `wsl --update --web-download` (then `--install` if needed) and discovers `wsl.exe` via `Get-Command` when System32 is missing (WOW64). Native `wsl`/`winget` calls use `SilentlyContinue` and `$LASTEXITCODE` so Windows PowerShell 5.1 does not treat stderr as a terminating error. If WSL is already installed, Set only retries the pin (no second `--update`). Pin add failure does not fail Set. Keep WSL current after bootstrap with `Update-Packages.ps1`.
- For `ensure: Absent`, the generator unpins `Microsoft.WSL` before emitting `WinGetPackage` Absent with `dependsOn: Microsoft.WSL.Unpin` so uninstall cannot run while the blocking pin is still in place.
- `Install-Packages.ps1` skips `winget install` for `Microsoft.WSL` and calls `Update-Wsl` (same as configure). A blocking pin would otherwise fail winget with a pin error, not `0x80073d28`, so the old fallback never ran.
- `Update-Wsl` uses a `wsl.exe` PATH fallback and `--install --web-download` when `Get-WslExePath` is null, matching SetScript bootstrap
- `winget configure` no longer emits `WinGetPackage` for `Microsoft.WSL` Present, so a MSIX `0x80073d28` cannot abort the web-download Script
- WSL pin detection matches `Microsoft.WSL` as its own token (not `Microsoft.WSLg` / `Microsoft.WSLPreview`)

## [1.1.16] - 2026-09-05

### Added
- `Herdr.Herdr.Preview` to `development` category

## [1.1.15] - 2026-08-24

### Added
- `MoonlightGameStreamingProject.Moonlight` to `media` category

### Fixed
- `validate-config.yml` failed on winget 1.11: `configure validate` does not accept `--accept-configuration-agreements`, and `configure test` exits 1 on a clean CI runner when packages are not installed

## [1.1.14] - 2026-08-03

### Added
- `JGraph.Draw` to `productivity` category

## [1.1.13] - 2026-07-30

### Added
- `GOG.Galaxy` to `media` category

## [1.1.12] - 2026-07-25

### Added
- `xAI.GrokBuild` (Grok Build CLI agent) to `development` category
- GitHub Actions workflow `.github/workflows/validate-config.yml` for WinGet DSC validation

### Removed
- Deduplicated `Hashicorp.Terraform` from `development` category (retained under `cloud_infrastructure`)

## [1.1.11] - 2026-06-03

### Added
- GitHub.CopilotApp

## [1.1.10] - 2026-05-29

### Added
- Hashicorp.TerraformLanguageServer to `development` category

## [1.1.9] - 2026-05-29

### Added
- Hashicorp.Terraform to `development` category

## [1.1.8] - 2026-05-26

### Removed
- Proton.ProtonDrive

## [1.1.7] - 2026-05-24

### Added
- Google.Antigravity
- Google.AndroidStudio
- Google.GoogleDrive
- Google.Chrome

## [1.1.6] - 2026-05-21

### Added
- Proton.ProtonPass.CLI to `security` category

## [1.1.5] - 2026-05-20

### Changed
- Commented out `Canonical.Ubuntu.2604` from `containers_virtualization` category because it isn't available on winget yet.
 
## [1.1.4] - 2026-05-20

### Removed
- Removed Bambu Studio slicer from `printing_3d` category

## [1.1.3] - 2026-05-16

### Added
- README Legacy Mode section now documents `-Thermonuclear` switch for bulk uninstallation
  of all managed packages via `Install-Packages.ps1`

### Fixed
- `regenerate-config.yml` failed with `GitHub Actions is not permitted to create or approve
  pull requests` — replaced PR-based approach with a direct commit and push to `develop`;
  `[skip ci]` on the bot commit prevents cascading triggers into `release.yml`
- `regenerate-config.yml` used `git add -A` when staging changes, which would accidentally
  stage temp files (`changes.json`, `changelog_entry.md`) — replaced with targeted staging
  of only `.configurations/configuration.dsc.yaml` and `CHANGELOG.md`
- `regenerate-config.yml` and `release.yml` had no concurrency guard; added separate
  `concurrency` groups (`regenerate-dsc` with `cancel-in-progress: true`, `release` with
  `cancel-in-progress: false`) to prevent race conditions on combined pushes

## [1.1.2] - 2026-05-16

### Added
- `Canonical.Ubuntu.2604` — Ubuntu 26.04 LTS (WSL distro) under Containers & virtualization
- Renamed section header `Containers & virtualisation` → `Containers & virtualization`

### Removed
- Pruned all stale `Absent` tombstones from `configuration.dsc.yaml`; the following
  packages were previously tracked as `ensure: Absent` (enforcing uninstallation) and
  are now completely removed from the configuration (no longer managed by winget DSC):
  - Development: `Python.Python.3.10`, `Python.Launcher`,
    `RubyInstallerTeam.RubyWithDevKit.3.4`, `Microsoft.VisualStudioCode`,
    `Microsoft.VisualStudioCode.Insiders`, `Anysphere.Cursor`, `OpenAI.Codex`
  - Containers: `Canonical.Ubuntu.2404`, `Canonical.Ubuntu.2204`
  - Productivity: `PDFLabs.PDFtk.Free`, `FlorianHeidenreich.Mp3tag`
  - Media: `HandBrake.HandBrake`, `LIGHTNINGUK.ImgBurn`, `Transmission.Transmission`,
    `GOG.Galaxy`, `TASEmulators.BizHawk`
  - Browsers: `eloston.ungoogled-chromium`
  - Communication: `Element.Element`

## [1.1.1] - 2026-05-16

### Added
- GitHub releases (published and draft) now include `configuration.dsc.yaml` as a
  downloadable asset, attached automatically by the release workflow
- README instructions for applying winget configuration directly from release (without cloning repo)

### Fixed
- `regenerate-config.yml` trigger branch was `main` — corrected to `develop` to match
  where package changes are authored
- `regenerate-config.yml` created PRs targeting `main` instead of `develop` — corrected
  so the generated config is proposed back into the same working branch
- `regenerate-config.yml` did not read the `pruned` list from `changes.json` — now
  tracked as a step output and included in the commit message and PR body summary
- `regenerate-config.yml` PR body incorrectly stated packages were "pushed to `main`" —
  corrected to `develop`
- `release.yml` / `create_release.py` crashed with exit code 1 because `gh release create`
  was called with `--target main`, but the repository has no `main` branch — now uses
  `GITHUB_SHA` to target the exact triggering commit instead
- `create_release.py` CHANGELOG parser silently skipped version entries with a `v` prefix
  (e.g. `[v1.1.1]`) due to a strict regex — updated to tolerate an optional `v`
- `actions/checkout@v4` updated to `v6` in both workflow files to resolve Node.js 20
  deprecation warnings ahead of the June 2026 forced migration to Node.js 24


## [1.1.0] - 2026-05-16

### Added
- `JAMSoftware.TreeSize.Free` — TreeSize Free disk usage analyser
- `martinrotter.RSSGuard5` — RSS Guard feed reader
- `Mozilla.Firefox` — Firefox browser
- GitHub Actions workflow (`regenerate-config.yml`) that automatically regenerates
  `configuration.dsc.yaml` and opens a PR whenever `winget-packages.yml` changes on `main`
- `-Thermonuclear` switch to `Install-Packages.ps1` for bulk uninstallation of all managed packages

### Fixed
- `New-WingetConfiguration.ps1` failed to parse entirely in PowerShell 5.1 due to Unicode
  characters (`—`, `─`, `✓`) in string literals being misread as string delimiters when the
  file lacked a UTF-8 BOM — all string literals now use ASCII-safe equivalents
- `New-WingetConfiguration.ps1` file was corrupted (four concatenated copies of the script
  with embedded AI prose) — replaced with a single clean 654-line version
- `New-WingetConfiguration.ps1` `-ChangesOutputFile` parameter was declared but never
  implemented — now writes JSON with `added`, `removed`, and `pruned` package lists
- `New-WingetConfiguration.ps1` stale-tombstone pruning (`Read-DscEnsureMap`) was defined
  but never called — now correctly detects and prunes `Absent` entries that are no longer
  in the previous Git snapshot
- `New-WingetConfiguration.ps1` output file was only written when `-Force` was set or the
  file already existed; on a clean checkout the script silently showed a dry-run preview
  instead of creating the file

### Removed
- Development: `Python.Python.3.10`, `Python.Launcher`, `RubyInstallerTeam.RubyWithDevKit.3.4`,
  `LLVM.LLVM`, `Microsoft.VisualStudioCode`, `Microsoft.VisualStudioCode.Insiders`
- Containers: `Canonical.Ubuntu.2404`, `Canonical.Ubuntu.2204`
- Productivity: `PDFLabs.PDFtk.Free`, `FlorianHeidenreich.Mp3tag`
- Media: `HandBrake.HandBrake`, `LIGHTNINGUK.ImgBurn`, `Transmission.Transmission`,
  `GOG.Galaxy`, `TASEmulators.BizHawk`
- Browsers: `eloston.ungoogled-chromium`
- Communication: `Element.Element`

## [1.0.2] - 2026-04-19

### Added
- Telegram
- NodeJS
- Claude Code

### Removed
- Neovim (unused)
- Visual Studio 2022 (unused)
- PocketCasts (failing)
- Anaconda (failing)
- miniconda (failing)

## [1.0.1] - 2026-04-18

### Added

- Prerequisites section in README covering PowerShell 7.6.0+ installation and execution policy setup
- CHANGELOG.md to track project changes
- GitHub Actions release workflow that automatically creates GitHub releases from CHANGELOG entries
