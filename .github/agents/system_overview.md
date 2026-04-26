# 🛡️ System Overview: Winget Package Configuration System

## 🎯 1. Purpose and Core Principle

This repository manages Windows package configurations using a **declarative, idempotent** approach powered by PowerShell and the `winget` (Windows Package Manager) CLI.

**Goal:** To establish a single, reliable source of truth for the software required on a Windows machine, ensuring that package installations are always in the desired state, regardless of the initial state.

**Core Principle:** We define the desired system state in a YAML file. The system then calculates the necessary actions (installing, updating, or removing) to reach that state, treating the entire process as code.

---

## ⚙️ 2. System Architecture & Components

The system operates through a three-stage pipeline, managed by distinct artifacts:

### 📁 `winget-packages.yml` (The Source of Truth)
*   **Role:** This is the single point of entry for defining required software.
*   **Usage:** Agents must directly edit this file to add, remove, or update package definitions.
*   **Structure:** Packages are organized under logical categories (e.g., `development`, `browsers`) purely for human readability; all categories are merged during the generation step.
*   **Example:**
    ```yaml
    packages:
      development:
        - Git.Git
        - GitHub.cli
    ```

### ⚙️ `New-WingetConfiguration.ps1` (The Generator)
*   **Role:** This is the central processing engine.
*   **Mechanism:** The script reads `winget-packages.yml` and performs a crucial **diff** comparison against the last committed version (Git HEAD).
*   **Key Function:** This diffing capability is vital as it allows the system to automatically mark packages for *removal* (`ensure: Absent`), enabling a reliable cleanup process.
*   **Output:** It emits the structured configuration file: `.configurations/configuration.dsc.yaml`.

### 📄 `.configurations/configuration.dsc.yaml` (The Artifact)
*   **Nature:** This file is **GENERATED** by the script, never written manually.
*   **Format:** It uses the Desired State Configuration (DSC) format understood by `winget configure`.
*   **🚨 Agent Directive:** Agents **MUST NEVER** manually modify this file. Its contents are a direct, derived output of Step 2.

---

## ✨ 3. Agent Directives Summary (For AI Automation)

This section serves as a strict, step-by-step planning guide for automation.

1.  **Pre-flight Check (Priority):** Before any operation, the agent **must** validate the system prerequisites (Admin rights, PS version, Tool availability).
2.  **Immutability:** Treat `.configurations/configuration.dsc.yaml` as a read-only artifact.
3.  **Execution Order (Immutable Flow):** The execution sequence is mandatory:
    **`winget-packages.yml` $\rightarrow$ `New-WingetConfiguration.ps1` $\rightarrow$ `winget configure`**
4.  **Skill Utilization:** For robust setup validation, agents should prioritize calling helper validation functions from the `agent-skills/` directory to perform environment checks *before* initiating the main workflow.