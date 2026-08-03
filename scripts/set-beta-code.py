#!/usr/bin/env python3
"""Set the private-beta access code.

Writes only the salted hash into the Swift source, so the code itself never
appears in a public repository.

    python scripts/set-beta-code.py "my new code"

The code is normalised the same way the app normalises what a tester types:
trimmed and lowercased. Anything else would reject people over an
autocapitalised first letter.

A reminder about what this protects, because it is easy to forget once it is a
password field on a screen: it gates entry to the beta, not anyone's
recordings. The comparison happens on the device and the binary is
extractable, so a determined person gets past it. That is fine for choosing who
tests an app; it would not be fine for guarding data.
"""

from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Somna" / "Core" / "Security" / "BetaAccessCode.swift"
SALT = "somna.beta.2026.v1"


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 1

    code = sys.argv[1].strip().lower()
    if len(code) < 4:
        print("Refusing a code shorter than four characters: it would not even "
              "be a speed bump.", file=sys.stderr)
        return 1

    digest = hashlib.sha256((SALT + code).encode("utf-8")).hexdigest()

    text = SOURCE.read_text(encoding="utf-8")
    updated, count = re.subn(
        r'(private static let expectedHash =\n        ")[0-9a-f]{64}(")',
        rf"\g<1>{digest}\g<2>",
        text,
    )
    if count != 1:
        print("Could not find the hash to replace in BetaAccessCode.swift.",
              file=sys.stderr)
        return 1

    SOURCE.write_text(updated, encoding="utf-8")

    print(f"Beta code set. Hash: {digest}")
    print("The code itself is not stored anywhere — write it down, and give it "
          "to your testers directly rather than in the repository.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
