# Agent Skills

This directory contains **Agent Skills** for the `winget-configure` repository,
following the [Microsoft Agent Framework Skills specification](https://learn.microsoft.com/en-us/agent-framework/agents/skills).

Each skill is a self-contained directory with a `SKILL.md` file and optional
subdirectories for scripts, references, and assets. A compatible skills provider
discovers them automatically by searching for `SKILL.md` files up to two levels deep.

---

## Directory Layout

```
agent-skills/
├── README.md                                  ← you are here
└── documentation-and-naming/                  ← one directory per skill
    ├── SKILL.md                               ← required: frontmatter + instructions
    └── references/
        └── quick-reference.md                 ← cheat sheet, loaded on demand
```

New skills go directly under `agent-skills/`. One concern per skill directory.

---

## Skill Directory Structure

Each skill directory follows this layout:

```
<skill-name>/
├── SKILL.md          # Required — YAML frontmatter + instruction body (< 500 lines)
├── scripts/          # Optional — executable code the agent can run
├── references/       # Optional — reference docs loaded on demand
└── assets/           # Optional — templates and static resources
```

Only `SKILL.md` is required. Add subdirectories only when the content exists.

---

## SKILL.md Frontmatter

Every `SKILL.md` opens with a YAML frontmatter block:

```yaml
---
name: skill-directory-name
description: What the skill does and when to use it. Include keywords that help
  the agent recognise relevant tasks. Max 1024 characters.
license: MIT
compatibility: Environment requirements, applicable file types, constraints.
  Max 500 characters.
metadata:
  author: github-username
  version: "MAJOR.MINOR.PATCH"
---
```

| Field | Required | Constraints |
|---|---|---|
| `name` | Yes | Max 64 chars. Lowercase letters, numbers, and hyphens only. Must not start or end with a hyphen or contain consecutive hyphens. **Must match the parent directory name exactly.** |
| `description` | Yes | Max 1024 chars. What the skill does and when to use it. Include keywords agents use to match tasks. |
| `license` | No | License identifier or path to bundled license file. |
| `compatibility` | No | Max 500 chars. File types, tools, OS requirements, or other constraints. |
| `metadata` | No | Arbitrary key-value pairs. Use at minimum `author` and `version`. |
| `allowed-tools` | No | Space-delimited list of pre-approved tools the skill may invoke. Experimental. |

---

## Progressive Disclosure

Skills load in three stages to keep the agent's context window lean:

| Stage | Tokens | What happens |
|---|---|---|
| **Advertise** | ~100 per skill | `name` and `description` are injected into the system prompt. The agent knows what skills exist. |
| **Load** | < 5 000 recommended | Agent calls `load_skill` — the full `SKILL.md` body is returned with detailed instructions. |
| **Read resources** | As needed | Agent calls `read_skill_resource` to fetch files from `references/`, `assets/`, or `scripts/` only when required. |

Design skill content with this in mind:

- **`description`** — write it as a tight capability statement with task-recognition
  keywords. This is the only thing the agent sees until it decides to load the skill.
- **`SKILL.md` body** — concise, actionable rules. Stay under 500 lines. If content
  is reference material (tables, extended examples, templates), move it to
  `references/` so it is fetched on demand rather than loaded every time.
- **`references/`** — detailed examples, cheat sheets, policy documents, templates.
  Named with `kebab-case.md`.

---

## Available Skills

| Skill | Description | Key references |
|---|---|---|
| [`documentation-and-naming`](documentation-and-naming/SKILL.md) | Naming conventions and documentation standards for PowerShell, YAML, and Markdown files in this repository. Use when creating, editing, or reviewing any file. | [`quick-reference.md`](documentation-and-naming/references/quick-reference.md) |

---

## Using Skills with an Agent

### GitHub Copilot (VS Code)

Reference the skill directory in `.github/copilot-instructions.md` to make it
available as persistent workspace context:

```markdown
When editing any file in this repository, apply the conventions in
agent-skills/documentation-and-naming/SKILL.md.

For detailed examples and a full cheat sheet, refer to
agent-skills/documentation-and-naming/references/quick-reference.md.
```

Attach a skill file directly in Copilot Chat with `#file:`:

```
#file:agent-skills/documentation-and-naming/SKILL.md
Refactor the helpers module to match project standards.
```

### Cursor

Reference skill files with `@`:

```
@agent-skills/documentation-and-naming/SKILL.md
Update this module to follow project conventions.
```

### Microsoft Agent Framework (Python)

Point a `SkillsProvider` at this directory and the framework discovers skills
automatically:

```python
from pathlib import Path
from agent_framework import SkillsProvider

skills_provider = SkillsProvider(
    skill_paths=Path(__file__).parent / "agent-skills"
)
```

The provider searches up to two levels deep for `SKILL.md` files, validates
frontmatter, and exposes `load_skill` and `read_skill_resource` tools to the agent.

### Any other agent

Paste `SKILL.md` content into the system prompt or attach it as a context document.
Load reference files only when the agent needs them.

---

## Adding a New Skill

1. **Create a directory** under `agent-skills/` using `kebab-case`. The name must
   satisfy the `name` field constraints (lowercase, letters/numbers/hyphens, no leading
   or trailing hyphens, no consecutive hyphens).

2. **Create `SKILL.md`** inside that directory. Set `name` to exactly match the
   directory name. Fill in all required frontmatter fields.

3. **Write the instruction body** in the Markdown section after the frontmatter. Target
   under 500 lines. Cover one concern per skill.

4. **Add subdirectories** as needed:
   - `references/` — reference docs, cheat sheets, extended examples
   - `assets/` — templates, static files the agent might render or fill in
   - `scripts/` — executable scripts the agent can run via `run_skill_script`

5. **Add a row** to the Available Skills table in this README.

6. **Version** the skill starting at `"1.0.0"`. Follow Semantic Versioning:
   - `MAJOR` — a rule is removed or inverted (breaking change)
   - `MINOR` — a new rule or section is added
   - `PATCH` — clarification, typo fix, or new example

---

## Skill Naming Rules (Summary)

| Rule | Example |
|---|---|
| Lowercase letters, numbers, hyphens | `documentation-and-naming` |
| Must match `name` field in frontmatter | dir `expense-report/` → `name: expense-report` |
| No leading or trailing hyphen | ~~`-my-skill`~~, ~~`my-skill-`~~ |
| No consecutive hyphens | ~~`my--skill`~~ |
| Max 64 characters | — |