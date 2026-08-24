# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.15] - 2026-08-24

### Added
- `MoonlightGameStreamingProject.Moonlight` to `media` category

### Fixed
- `validate-config.yml` passed `--accept-configuration-agreements` to `winget configure validate`, which winget 1.11 does not accept on that subcommand

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
