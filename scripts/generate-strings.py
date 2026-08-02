#!/usr/bin/env python3
"""Generate Somna/Resources/Localizable.xcstrings.

Two sources, each authoritative for one thing:

* **English** comes from the Swift source. Every `String(localized:defaultValue:)`
  call carries its own English text, so the code cannot drift from the catalogue.
* **French** comes from `scripts/i18n/fr.json`, keyed identically.

The script fails when a key has no French translation. That turns "we forgot to
translate the new screen" from something a beta tester discovers into something
CI does, which is the whole point of running it there.

Keys built at runtime (event phrasing, calibration advice, the time-of-day
greeting) cannot be extracted from source, so `fr.json` carries their English
text too, under `"dynamic"`.

Usage:
    python scripts/generate-strings.py           # write the catalogue
    python scripts/generate-strings.py --check   # verify only, used by CI
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE_DIR = ROOT / "Somna"
FRENCH_FILE = ROOT / "scripts" / "i18n" / "fr.json"
OUTPUT = ROOT / "Somna" / "Resources" / "Localizable.xcstrings"

# Matches String(localized: "key", defaultValue: "text") across line breaks.
STATIC_CALL = re.compile(
    r'String\(\s*localized:\s*"([^"]+)"\s*,\s*'
    r'defaultValue:\s*"((?:[^"\\]|\\.)*)"',
    re.S,
)


def extract_english_from_source() -> dict[str, str]:
    found: dict[str, str] = {}
    for path in sorted(SOURCE_DIR.rglob("*.swift")):
        text = path.read_text(encoding="utf-8")
        for key, value in STATIC_CALL.findall(text):
            # Literals containing Swift interpolation cannot be carried across
            # verbatim: the catalogue needs positional placeholders (%1$lld)
            # rather than `\(expression)`. Those keys are declared by hand in
            # the "dynamic" section instead, with the placeholders written out.
            if "\\(" in value:
                continue

            # Unescape the few sequences Swift allows in a literal.
            value = value.replace('\\"', '"').replace("\\n", "\n").replace("\\\\", "\\")
            if key in found and found[key] != value:
                print(f"  warning: '{key}' has two different English texts", file=sys.stderr)
            found[key] = value
    return found


def unit(value: str) -> dict:
    return {"stringUnit": {"state": "translated", "value": value}}


def localisation(value) -> dict:
    """Renders one language entry, plural or not.

    A plural entry is a dict of CLDR categories. Without it, a count of one
    reads "1 coughs were detected" in English and "1 toux ont ete detectees" in
    French - wrong in both, and wrong on exactly the nights where the count is
    smallest and most closely read.
    """
    if isinstance(value, dict):
        return {
            "variations": {
                "plural": {category: unit(text) for category, text in value.items()}
            }
        }
    return unit(value)


def build_catalogue(english: dict, french: dict) -> dict:
    strings = {}
    for key in sorted(english):
        strings[key] = {
            "extractionState": "manual",
            "localizations": {
                "en": localisation(english[key]),
                "fr": localisation(french[key]),
            },
        }
    return {"sourceLanguage": "en", "strings": strings, "version": "1.0"}


def main() -> int:
    check_only = "--check" in sys.argv

    data = json.loads(FRENCH_FILE.read_text(encoding="utf-8"))
    french = dict(data["translations"])
    dynamic = data["dynamic"]

    english = extract_english_from_source()
    for key, entry in dynamic.items():
        english[key] = entry["en"]
        french[key] = entry["fr"]

    missing = sorted(set(english) - set(french))
    unused = sorted(set(french) - set(english))

    for key in missing:
        print(f"  MISSING French translation: {key}", file=sys.stderr)
    for key in unused:
        print(f"  stale French entry (no longer in source): {key}", file=sys.stderr)

    if missing:
        print(f"\n{len(missing)} key(s) have no French translation.", file=sys.stderr)
        return 1

    catalogue = build_catalogue(english, {k: french[k] for k in english})
    rendered = json.dumps(catalogue, ensure_ascii=False, indent=2, sort_keys=True) + "\n"

    if check_only:
        current = OUTPUT.read_text(encoding="utf-8") if OUTPUT.exists() else ""
        if current != rendered:
            print("Localizable.xcstrings is out of date. Run scripts/generate-strings.py.",
                  file=sys.stderr)
            return 1
        print(f"Localizable.xcstrings is up to date - {len(english)} keys, 2 languages.")
        return 0

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(rendered, encoding="utf-8")
    print(f"Wrote {OUTPUT.relative_to(ROOT)} - {len(english)} keys, 2 languages.")
    if unused:
        print(f"({len(unused)} stale French entries left in place, harmless.)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
