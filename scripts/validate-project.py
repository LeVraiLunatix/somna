#!/usr/bin/env python3
"""Validate project.yml without Xcode.

This is the only meaningful check available on Windows, where the project is
developed. It catches the mistakes that would otherwise only surface minutes
into a CI run: broken YAML, a missing target, a deployment target that drifted
away from the one the code assumes, or an accidentally added background mode.

Usage:  python scripts/validate-project.py
"""

from __future__ import annotations

import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("PyYAML is required:  python -m pip install pyyaml")

ROOT = Path(__file__).resolve().parent.parent
PROJECT_FILE = ROOT / "project.yml"

EXPECTED_TARGETS = {"Somna", "SomnaTests", "SomnaUITests"}
EXPECTED_DEPLOYMENT_TARGET = "26.0"
EXPECTED_BUNDLE_ID = "com.somna.app"
# Somna must never silently acquire a second background mode: each one is a
# battery and App Review liability, and `audio` is the only one it needs.
EXPECTED_BACKGROUND_MODES = ["audio"]

failures: list[str] = []
checks: list[str] = []


def check(condition: bool, label: str, detail: str = "") -> None:
    if condition:
        checks.append(label)
    else:
        failures.append(f"{label}{' -> ' + detail if detail else ''}")


def main() -> int:
    if not PROJECT_FILE.exists():
        sys.exit(f"project.yml not found at {PROJECT_FILE}")

    with PROJECT_FILE.open(encoding="utf-8") as handle:
        project = yaml.safe_load(handle)

    check(project.get("name") == "Somna", "project name is Somna")

    deployment = (
        project.get("options", {}).get("deploymentTarget", {}).get("iOS")
    )
    check(
        str(deployment) == EXPECTED_DEPLOYMENT_TARGET,
        f"deployment target is iOS {EXPECTED_DEPLOYMENT_TARGET}",
        f"found {deployment!r}",
    )

    targets = project.get("targets", {})
    check(
        set(targets) == EXPECTED_TARGETS,
        "all three targets are declared",
        f"found {sorted(targets)}",
    )

    app = targets.get("Somna", {})
    app_settings = app.get("settings", {}).get("base", {})
    check(
        app_settings.get("PRODUCT_BUNDLE_IDENTIFIER") == EXPECTED_BUNDLE_ID,
        f"bundle identifier is {EXPECTED_BUNDLE_ID}",
        f"found {app_settings.get('PRODUCT_BUNDLE_IDENTIFIER')!r}",
    )

    info = app.get("info", {}).get("properties", {})
    check(
        info.get("UIBackgroundModes") == EXPECTED_BACKGROUND_MODES,
        "audio is the only background mode",
        f"found {info.get('UIBackgroundModes')!r}",
    )
    check(
        bool(info.get("NSMicrophoneUsageDescription", "").strip()),
        "microphone usage description is present",
    )
    check(
        info.get("UISupportedInterfaceOrientations")
        == ["UIInterfaceOrientationPortrait"],
        "app is portrait-only",
    )
    check(
        info.get("ITSAppUsesNonExemptEncryption") is False,
        "export compliance is declared",
    )

    base = project.get("settings", {}).get("base", {})
    check(base.get("TARGETED_DEVICE_FAMILY") == "1", "iPhone-only device family")
    check(str(base.get("SWIFT_VERSION")) == "6.0", "Swift 6 language mode")
    check(
        "MARKETING_VERSION" in base and "CURRENT_PROJECT_VERSION" in base,
        "versioning is CI-overridable",
    )

    check("Somna" in project.get("schemes", {}), "the Somna scheme exists")

    # Every referenced source root must actually exist, or XcodeGen produces an
    # empty target that links to nothing and fails late.
    for name, target in targets.items():
        for source in target.get("sources", []):
            path = ROOT / source["path"]
            check(path.is_dir(), f"source root exists for {name}: {source['path']}")

    for line in checks:
        print(f"  ok    {line}")
    for line in failures:
        print(f"  FAIL  {line}")

    print()
    if failures:
        print(f"{len(failures)} check(s) failed out of {len(checks) + len(failures)}.")
        return 1

    print(f"project.yml is valid - {len(checks)} checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
