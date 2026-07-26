#!/usr/bin/env python3
"""
Parse CHANGELOG.md (keepachangelog.com format) and manage GitHub releases.

Behaviour on each run:
  1. Versioned release  — if the topmost dated section (e.g. [1.0.1] - 2026-04-18)
                          has no corresponding GitHub release/tag, create one and
                          clean up any draft releases for that version.
  2. Draft release      — if the [Unreleased] section has content, infer the next
                          SemVer number from the change-type headings, delete any
                          existing draft for that inferred version, and publish a
                          fresh draft tagged  v<version>-draft-<YYYYMMDD-HHmm>.

SemVer inference from [Unreleased] change types (keepachangelog.com):
  ### Breaking            → MAJOR bump  (breaking API / behaviour)
  ### Added / Deprecated  → MINOR bump  (new functionality)
  ### Fixed / Changed /
  ### Removed / Security  → PATCH bump  (package-list removals are not API breaks)
  Highest priority wins (MAJOR > MINOR > PATCH).
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone


# ---------------------------------------------------------------------------
# CHANGELOG parsing
# ---------------------------------------------------------------------------

def parse_changelog(path: str = "CHANGELOG.md") -> tuple[str, list[tuple[str, str, str]]]:
    """Return ``(unreleased_content, versioned_releases)``.

    *unreleased_content* is the stripped text under ``## [Unreleased]``.
    *versioned_releases* is a list of ``(version, date, notes)`` tuples in
    document order (newest first).
    """
    with open(path, encoding="utf-8") as fh:
        content = fh.read()

    # --- [Unreleased] section -----------------------------------------------
    unreleased_match = re.search(
        r"^## \[Unreleased\]\s*\n(.*?)(?=^## \[|\Z)",
        content,
        re.MULTILINE | re.DOTALL,
    )
    unreleased_content = unreleased_match.group(1).strip() if unreleased_match else ""

    # --- Versioned sections --------------------------------------------------
    version_re = re.compile(
        r"^## \[v?(\d+\.\d+\.\d+)\] - (\d{4}-\d{2}-\d{2})\s*\n(.*?)(?=^## \[|\Z)",
        re.MULTILINE | re.DOTALL,
    )
    versioned: list[tuple[str, str, str]] = [
        (m.group(1), m.group(2), m.group(3).strip())
        for m in version_re.finditer(content)
    ]

    return unreleased_content, versioned


def infer_next_version(current_version: str, unreleased_content: str) -> str:
    """Infer the next SemVer from the change-type headings in *unreleased_content*."""
    major, minor, patch = map(int, current_version.split("."))

    has_major = bool(re.search(r"^### Breaking", unreleased_content, re.MULTILINE))
    has_minor = bool(re.search(r"^### (?:Added|Deprecated)", unreleased_content, re.MULTILINE))

    if has_major:
        return f"{major + 1}.0.0"
    if has_minor:
        return f"{major}.{minor + 1}.0"
    return f"{major}.{minor}.{patch + 1}"


# ---------------------------------------------------------------------------
# GitHub CLI helpers
# ---------------------------------------------------------------------------

def _run(cmd: list[str], check: bool = True) -> subprocess.CompletedProcess:
    result = subprocess.run(cmd, capture_output=True, text=True)
    if check and result.returncode != 0:
        print(f"ERROR: command failed: {' '.join(cmd)}", file=sys.stderr)
        print(result.stderr, file=sys.stderr)
        sys.exit(1)
    return result


def list_releases() -> list[dict]:
    """Return all GitHub releases (up to 200) as a list of dicts."""
    result = _run([
        "gh", "release", "list",
        "--json", "tagName,isDraft,name",
        "--limit", "200",
    ])
    return json.loads(result.stdout)


def release_tag_exists(tag: str, releases: list[dict]) -> bool:
    """Return True if a *published* (non-draft) release with *tag* exists."""
    return any(r["tagName"] == tag and not r["isDraft"] for r in releases)


def find_draft_releases_for_version(version: str, releases: list[dict]) -> list[dict]:
    """Return all draft releases whose tag starts with ``v<version>-draft-``."""
    prefix = f"v{version}-draft-"
    return [r for r in releases if r["isDraft"] and r["tagName"].startswith(prefix)]


def delete_release(tag: str) -> None:
    """Delete a GitHub release and attempt to clean up its git tag.

    ``--cleanup-tag`` is intentionally avoided because draft releases do not
    always have a corresponding git ref, and the GitHub API returns HTTP 422
    ("Reference does not exist") in that case, failing the whole workflow.
    Instead the release is deleted first, then the tag deletion is attempted
    separately and any 422 error is silently ignored.
    """
    print(f"    Deleting old release {tag} …")
    _run(["gh", "release", "delete", tag, "--yes"])

    # Best-effort tag cleanup — ignore 422 if the ref was never created
    result = _run(
        ["gh", "api", "--method", "DELETE",
         f"/repos/{{owner}}/{{repo}}/git/refs/tags/{tag}"],
        check=False,
    )
    if result.returncode != 0 and "Reference does not exist" not in result.stderr:
        print(f"    Warning: could not delete tag {tag}: {result.stderr.strip()}",
              file=sys.stderr)


DSC_CONFIG_ASSET = ".configurations/configuration.dsc.yaml"


def create_release(tag: str, title: str, notes: str, *, draft: bool = False) -> None:
    """Create a GitHub release (and its git tag) targeting the commit SHA or develop.

    Automatically attaches ``.configurations/configuration.dsc.yaml`` as a
    release asset when the file is present in the working tree.
    """
    cmd = [
        "gh", "release", "create", tag,
        "--title", title,
        "--notes", notes,
        "--target", os.environ.get("GITHUB_SHA", "develop"),
    ]
    if draft:
        cmd.append("--draft")
    if os.path.isfile(DSC_CONFIG_ASSET):
        cmd.append(DSC_CONFIG_ASSET)
        print(f"    Attaching asset: {DSC_CONFIG_ASSET}")
    else:
        print(f"    Warning: asset not found, skipping: {DSC_CONFIG_ASSET}", file=sys.stderr)
    _run(cmd)


# ---------------------------------------------------------------------------
# Main logic
# ---------------------------------------------------------------------------

def main() -> None:
    unreleased_content, versioned = parse_changelog()
    releases = list_releases()

    # -----------------------------------------------------------------------
    # 1. Published release for the topmost versioned CHANGELOG entry
    # -----------------------------------------------------------------------
    if versioned:
        top_version, top_date, top_notes = versioned[0]
        tag = f"v{top_version}"

        if release_tag_exists(tag, releases):
            print(f"Release {tag} already exists — skipping")
        else:
            print(f"New versioned entry found: {tag} ({top_date})")

            # Remove any draft releases that were tracking this version
            for draft in find_draft_releases_for_version(top_version, releases):
                delete_release(draft["tagName"])

            print(f"  Creating release {tag} …")
            create_release(tag, tag, top_notes, draft=False)
            print(f"  ✓ Created release {tag}")
    else:
        print("No versioned entries in CHANGELOG — skipping published release")

    # -----------------------------------------------------------------------
    # 2. Draft release for [Unreleased] content
    # -----------------------------------------------------------------------
    if not unreleased_content:
        print("No unreleased content — skipping draft release")
        return

    base_version = versioned[0][0] if versioned else "0.0.0"
    next_version = infer_next_version(base_version, unreleased_content)
    print(f"\nUnreleased content found — inferred next version: v{next_version}")

    # Replace any existing draft(s) for this inferred version
    old_drafts = find_draft_releases_for_version(next_version, releases)
    for old_draft in old_drafts:
        delete_release(old_draft["tagName"])

    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M")
    draft_tag = f"v{next_version}-draft-{timestamp}"

    print(f"  Creating draft release {draft_tag} …")
    create_release(draft_tag, f"Draft: v{next_version}", unreleased_content, draft=True)
    print(f"  ✓ Created draft release {draft_tag}")


if __name__ == "__main__":
    main()
