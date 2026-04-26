# 🚀 Standard Agent Workflow: Winget Package Configuration
## 🎯 Goal
This guide outlines the mandatory, three-step process for achieving a declarative, idempotent configuration of required packages on a Windows machine. Adhering to this precise sequence is crucial for the system to correctly generate and apply the desired state.

---

## 📝 Workflow Overview
The process is a linear pipeline: **Input Definition $\rightarrow$ Artifact Generation $\rightarrow$ Enforcement**.

### 📂 Step 1: Modify the Desired State (Input Phase)
**Action:** An agent must modify the `winget-packages.yml` file.
**Task:**
1.  Add new package IDs.
2.  Remove obsolete package IDs.
3.  Reorganize or update package metadata within existing categories.
**💡 Crucial Point:** This file is the **single source of truth**. All changes must originate here.

### ⚙️ Step 2: Generate the Configuration Artifact (Processing Phase)
**Action:** Execute the generator script.
**Command:** `./New-WingetConfiguration.ps1`
**Purpose:** This script reads the modified `winget-packages.yml` and performs a vital **diff** check against the last committed version (Git HEAD).
**Output:** It outputs the standardized Desired State Configuration (DSC) file: `.configurations/configuration.dsc.yaml`.
**✅ Validation Check:** After execution, the agent **must** confirm the presence of `.configurations/configuration.dsc.yaml` and verify that it accurately reflects all intended packages, including those marked for removal (`ensure: Absent`).

### ✅ Step 3: Apply the Configuration (Enforcement Phase)
**Goal:** Reconciliation—This step compares the actual state of the machine against the desired state defined in the DSC file and makes necessary changes.
**Command:** `winget configure -f .configurations\configuration.dsc.yaml`
**Output Analysis:**
*   The agent must parse the output to confirm successful reconciliation.
*   Specific attention should be paid to error logs to detect any resource failures (e.g., package ID not found, permissions denied).