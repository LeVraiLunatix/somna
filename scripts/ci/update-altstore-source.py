#!/usr/bin/env python3
"""Add a released build to the AltStore source.

The feed is a plain JSON file served straight from raw.githubusercontent.com.
That avoids GitHub Pages entirely: one fewer moving part, and one fewer thing
that can be misconfigured in a way nobody notices until a tester's install
fails.

Previous versions are kept rather than replaced. AltStore lets people install an
older build, which matters for a beta where a release can turn out to be worse
than the one before it.

Usage:
    python scripts/ci/update-altstore-source.py \\
        --version 0.1.0 --build 42 --size 4823910 \\
        --url https://github.com/.../Somna-0.1.0.ipa \\
        --notes-file release-notes.md
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
FEED = ROOT / "altstore" / "apps.json"

# Matches IPHONEOS_DEPLOYMENT_TARGET. AltStore uses it to refuse an install that
# would fail on the device rather than letting it fail after the download.
MINIMUM_OS_VERSION = "26.0"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--size", required=True, type=int)
    parser.add_argument("--url", required=True)
    parser.add_argument("--notes-file")
    parser.add_argument("--date")
    args = parser.parse_args()

    feed = json.loads(FEED.read_text(encoding="utf-8"))

    notes = "Private beta build."
    if args.notes_file:
        path = Path(args.notes_file)
        if path.exists():
            notes = path.read_text(encoding="utf-8").strip() or notes

    entry = {
        "version": args.version,
        "buildVersion": args.build,
        "date": args.date or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "localizedDescription": notes,
        "downloadURL": args.url,
        "size": args.size,
        "minOSVersion": MINIMUM_OS_VERSION,
    }

    app = feed["apps"][0]
    versions = app.setdefault("versions", [])

    # Re-running a release must not create a duplicate entry: workflows get
    # retried, and a feed with the same version twice confuses AltStore.
    versions = [
        existing for existing in versions
        if not (existing.get("version") == args.version
                and existing.get("buildVersion") == args.build)
    ]

    # Newest first — AltStore offers the first entry as the current version.
    app["versions"] = [entry] + versions

    FEED.write_text(
        json.dumps(feed, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    print(f"Added {args.version} ({args.build}), {args.size} bytes.")
    print(f"The source now offers {len(app['versions'])} version(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
