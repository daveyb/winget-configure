# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]


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
