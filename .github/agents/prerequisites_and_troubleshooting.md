# ⚠️ Prerequisites and Troubleshooting: Winget Package Configuration

This document serves as a mandatory reference for any agent or engineer interacting with the `winget-configure` system. Before any package deployment or configuration change, these prerequisites must be validated.

---

## 📋 Mandatory Prerequisites (Validation Checklist)

| Requirement | Details | Validation Command / Action |
| :--- | :--- | :--- |
| **Operating System** | Windows 10 (v1809+) or Windows 11. | Verify OS version. |
| **PowerShell** | PowerShell 7.6 or later (Recommended). | Run `pwsh --version`. |
| **Privileges** | Must run in an **Administrator (Elevated)** session. | Right-click terminal $\rightarrow$ Run as Administrator. |
| **Tools** | `winget` and `git` must be installed and in the system PATH. | Run `winget --version` and `git --version`. Both must return version numbers. |
| **Source Control** | Git must be initialized and committed to track previous states. | Verify `.git` directory and commit status. |

---

## 🩹 Troubleshooting Flowchart

When a configuration fails, follow this flowchart to diagnose the root cause:

| Symptom | Likely Root Cause | Recommended Remediation (Action) |
| :--- | :--- | :--- |
| `winget` command not found | `winget` is not in the PATH or a helper module is needed. | **Action:** Import helper modules: `Import-Module helpers\Ensure-Winget.psm1` and execute its exported function to bootstrap winget. |
| `Permission denied` | Insufficient privileges to write or modify system settings. | **Action:** Re-run the **entire three-step sequence** from an **elevated (Administrator)** PowerShell session. |
| DSC file is missing or empty. | The generator script was skipped, failed, or was run against a stale YAML. | **Action:** Ensure `New-WingetConfiguration.ps1` is run successfully in Step 2. Manually verify that `.configurations/configuration.dsc.yaml` was created. |
| Package ID failure | The package ID in `winget-packages.yml` is outdated. | **Action:** Manually search for the current, correct ID in the official [winget-pkgs repository](https://github.com/microsoft/winget-pkgs). |
| **Stale Configuration** | The desired state hasn't changed since the last commit. | **Action:** Run `git add winget-packages.yml` followed by a commit to force the generator to re-diff and update the DSC artifact. |
| **`Microsoft.WSL` / `0x80073d28`** | winget's WSL MSIX installer requires administrator privileges. | **Action:** Run `.\Update-Packages.ps1` or `wsl --update --web-download`. Do not retry `winget upgrade Microsoft.WSL`. |

---

## 💡 General Best Practices

*   **Execution Order:** Always remember the mandatory flow: **YAML Edit $\rightarrow$ Generate Script $\rightarrow$ Apply Config**. Never skip a step.
*   **Artifact Integrity:** The file `.configurations/configuration.dsc.yaml` is a derived artifact and should never be modified manually.
*   **Isolation:** Changes to the package list should be committed as a single atomic change set (a single commit) to ensure Git can properly track the diff and manage the package lifecycle.