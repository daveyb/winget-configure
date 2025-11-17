# Windows Package Manager Configuration

This repository contains configurations for automated package installation on Windows using Windows Package Manager (winget).

## Overview

There are two modes for installing packages, depending on your Windows account type:

### Mode 1: PowerShell Script (Recommended for Local Accounts)

**Use this method if you have a Windows 11 local (non-Microsoft) account.**

The `Install-Packages.ps1` script provides a straightforward way to install packages without requiring a Microsoft-connected account. This is the preferred method for users who:

- Have a local Windows account (not connected to a Microsoft account)
- Want to avoid Microsoft Store dependencies
- Need a simple, direct installation approach

#### Usage

```powershell
# Install all packages from the default list
.\Install-Packages.ps1

# Install with forced reinstallation
.\Install-Packages.ps1 -Force

# Quiet mode (minimal output)
.\Install-Packages.ps1 -Quiet

# Install specific packages only
.\Install-Packages.ps1 -PackageList @("Microsoft.PowerToys", "Git.Git")
```

#### Features

- ✅ Works with local Windows accounts
- ✅ No Microsoft Store authentication required
- ✅ Built-in error handling and progress reporting
- ✅ Checks for already-installed packages
- ✅ Detailed installation summary
- ⚠️ Requires administrator privileges

### Mode 2: WinGet Configure (Requires Microsoft Account)

**Use this method if you have a Microsoft-connected account.**

The `winget configure` command uses DSC (Desired State Configuration) YAML files to declaratively define your system configuration. This method requires:

- A Windows account connected to a Microsoft account
- Access to the Microsoft Store
- WinGet Configure feature enabled

#### Usage

```powershell
# Navigate to a configuration directory
cd .configurations\Common

# Apply the configuration
winget configure -f configuration.dsc.yaml

# Or specify the full path
winget configure -f .\.configurations\Development\configuration.dsc.yaml
```

#### Available Configurations

- **Common** - Essential packages for all users (PowerToys, VSCode, Chrome, etc.)
- **Development** - Development tools and environments
- **Git** - Git-related tools and utilities
- **Home** - Home/personal use packages

#### Features

- ✅ Declarative configuration management
- ✅ Idempotent installations (safe to run multiple times)
- ✅ Source control friendly (YAML format)
- ✅ Official Microsoft approach
- ⚠️ Requires Microsoft-connected account
- ⚠️ Requires Microsoft Store access

## Choosing the Right Mode

| Factor | Mode 1 (PowerShell) | Mode 2 (WinGet Configure) |
|--------|-------------------|--------------------------|
| Account Type | Local accounts ✅ | Microsoft accounts only |
| Microsoft Store | Not required ✅ | Required |
| Configuration Format | PowerShell array | YAML DSC files |
| Best For | Quick setup, local accounts | Infrastructure as Code, repeatability |
| Administration | Requires admin ⚠️ | Requires admin ⚠️ |

## Prerequisites

- Windows 10 (1809+) or Windows 11
- Windows Package Manager (winget) installed
- Administrator privileges
- Internet connection

## Package Lists

### PowerShell Script Packages

The `Install-Packages.ps1` script includes:

- **Cloud Tools**: AWS CLI, Azure CLI, Terraform
- **Development**: Git, GitHub CLI, Go, Python, Ruby, Zed
- **Linux/Containers**: Ubuntu, Incus, Rancher Desktop
- **Utilities**: PowerToys, Sysinternals Suite, Oh My Posh
- **Applications**: Spotify, Zoom, Ungoogled Chromium
- **Security/Privacy**: Proton Drive, Proton VPN, Tailscale
- **Media**: Calibre, Pocket Casts

### Configuration YAML Packages

Each configuration directory contains its own `configuration.dsc.yaml` file with packages specific to that use case. Check the individual files for details.

## Troubleshooting

### WinGet Not Found

If winget is not available, the PowerShell script includes a helper module (`helpers\Ensure-Winget.psm1`) that attempts to enable it automatically.

### Microsoft Store Required Error

If you see errors about Microsoft Store or account requirements when using `winget configure`, switch to Mode 1 (PowerShell script) instead.

### Package Not Found

Some packages may not be available in all regions or may have been renamed. Check the [winget-pkgs repository](https://github.com/microsoft/winget-pkgs) for the latest package IDs.

### Permission Denied

Both methods require administrator privileges. Right-click PowerShell and select "Run as Administrator" before executing the scripts.

## Contributing

Feel free to customize the package lists or configuration files to match your needs. The PowerShell script accepts custom package lists via the `-PackageList` parameter.

## License

This repository is provided as-is for personal and professional use.

## Resources

- [Windows Package Manager Documentation](https://learn.microsoft.com/windows/package-manager/)
- [WinGet CLI Reference](https://learn.microsoft.com/windows/package-manager/winget/)
- [DSC Configuration Reference](https://learn.microsoft.com/windows/package-manager/configuration/)
- [WinGet Packages Repository](https://github.com/microsoft/winget-pkgs)