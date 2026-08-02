#!/usr/bin/env bash
#
# Prints the UDID of the newest available iPhone simulator.
#
# Hardcoding a device name ("iPhone 17 Pro") is the classic way CI breaks
# silently when GitHub rotates its runner images. Asking simctl instead makes
# the pipeline survive image updates without a commit.
#
# Usage:  SIM_UDID=$(scripts/ci/select-simulator.sh)

set -euo pipefail

xcrun simctl list devices available --json | python3 -c '
import json
import re
import sys

runtimes = json.load(sys.stdin)["devices"]
best = None

for runtime, devices in runtimes.items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if match is None:
        continue
    version = (int(match.group(1)), int(match.group(2)))

    for device in devices:
        if not device.get("isAvailable"):
            continue
        if "iPhone" not in device.get("name", ""):
            continue
        candidate = (version, device["name"])
        if best is None or candidate > best[0]:
            best = (candidate, device["udid"], device["name"], version)

if best is None:
    sys.exit("No available iPhone simulator found on this runner.")

_, udid, name, version = best
print(f"Selected simulator: {name} (iOS {version[0]}.{version[1]})", file=sys.stderr)
print(udid)
'
