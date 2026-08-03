#!/usr/bin/env python3
"""Render Somna's app icon.

Generated rather than drawn so it can be produced from Windows, where no image
editor is part of the toolchain, and so a change to the mark is a diff rather
than a binary blob nobody can review.

The mark: a crescent moon with three arcs leaving its open edge. The moon says
night, the arcs say sound, and together they say what the app does. No stars —
every sleep app has stars — no text, and no gradient fine enough to disappear at
40 points.

iOS 26 wants three variants:
  * light   — the full artwork on its own background
  * dark    — artwork on transparency; iOS supplies the dark background
  * tinted  — greyscale on transparency; iOS applies the user's tint

Usage:  python scripts/make-app-icon.py
"""

from __future__ import annotations

import math
import struct
import zlib
from pathlib import Path

SIZE = 1024
ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "Somna" / "Resources" / "Assets.xcassets"

# Geometry, in fractions of the canvas so the mark scales with SIZE.
#
# iOS masks every icon with a squircle and then shrinks it into a home-screen
# grid, so anything past roughly 0.85 of the canvas is clipped or crowded. The
# whole mark — moon plus its widest arc — is therefore sized to sit inside
# 0.17…0.83 horizontally, and centred on that span rather than on the moon.
MOON_CENTRE = (0.39, 0.50)
MOON_RADIUS = 0.22
# The bite that makes the crescent. Offset up and right, slightly smaller, so the
# crescent thins towards its horns rather than ending abruptly.
BITE_CENTRE = (0.49, 0.425)
BITE_RADIUS = 0.21

ARCS = [
    # (radius, thickness, alpha) — spaced so they read as separate at small sizes,
    # and thick enough to survive being drawn at 40 points.
    (0.30, 0.024, 0.90),
    (0.37, 0.021, 0.60),
    (0.44, 0.018, 0.34),
]
# The arcs occupy the crescent's open side only: a full ring would read as a
# planet, not as sound leaving the moon. Kept to ±45° so the outermost one stays
# clear of the squircle's corners.
ARC_START = math.radians(-45)
ARC_END = math.radians(45)

MOON_COLOUR = (0xF4, 0xF3, 0xF7)

# One variant per palette in `ThemePalette`. The mark never changes — only the
# colour of the arcs and the tint of the night behind them — so the icon stays
# recognisable as Somna whichever one someone picks.
#
# `None` for the iconset name means the primary icon, which is what
# `setAlternateIconName(nil)` restores.
VARIANTS = {
    "AppIcon": {
        "arc": (0x6B, 0x8C, 0xF2),
        "top": (0x12, 0x16, 0x2C),
        "bottom": (0x05, 0x06, 0x0D),
    },
    "AppIconDawn": {
        "arc": (0xE0, 0x93, 0x4A),
        "top": (0x2A, 0x1B, 0x12),
        "bottom": (0x0D, 0x07, 0x05),
    },
    "AppIconTide": {
        "arc": (0x4F, 0xBE, 0xC6),
        "top": (0x0E, 0x24, 0x28),
        "bottom": (0x04, 0x0C, 0x0D),
    },
    "AppIconInk": {
        "arc": (0xC4, 0xC4, 0xCE),
        "top": (0x1A, 0x1A, 0x1E),
        "bottom": (0x07, 0x07, 0x09),
    },
}


def smoothstep(edge0: float, edge1: float, x: float) -> float:
    """Analytic anti-aliasing: one smooth ramp instead of supersampling."""
    if edge0 == edge1:
        return 0.0 if x < edge0 else 1.0
    t = max(0.0, min(1.0, (x - edge0) / (edge1 - edge0)))
    return t * t * (3 - 2 * t)


def blend(base, colour, alpha):
    return tuple(round(b + (c - b) * alpha) for b, c in zip(base, colour))


def coverage_circle(dx: float, dy: float, radius: float, feather: float) -> float:
    """How much of a pixel falls inside a circle, 0–1."""
    distance = math.hypot(dx, dy)
    return 1.0 - smoothstep(radius - feather, radius + feather, distance)


def render(variant: str, colours: dict) -> bytes:
    """Returns RGBA bytes for one appearance of one palette."""
    pixels = bytearray()
    feather = 1.5 / SIZE

    moon_cx, moon_cy = MOON_CENTRE
    bite_cx, bite_cy = BITE_CENTRE

    for y in range(SIZE):
        v = y / (SIZE - 1)
        for x in range(SIZE):
            u = x / (SIZE - 1)

            # --- Background -------------------------------------------------
            if variant == "light":
                base = tuple(
                    round(t + (b - t) * v)
                    for t, b in zip(colours["top"], colours["bottom"])
                )
                alpha = 1.0
            else:
                base = (0, 0, 0)
                alpha = 0.0

            colour = base

            # --- Arcs -------------------------------------------------------
            # Drawn before the moon so the moon always sits on top of them.
            adx, ady = u - moon_cx, v - moon_cy
            angle = math.atan2(ady, adx)
            distance = math.hypot(adx, ady)

            if ARC_START <= angle <= ARC_END:
                for radius, thickness, arc_alpha in ARCS:
                    band = 1.0 - smoothstep(
                        thickness * 0.5 - feather, thickness * 0.5 + feather,
                        abs(distance - radius)
                    )
                    if band <= 0:
                        continue
                    # Fade towards the ends so the arcs do not stop with a hard edge.
                    taper = 1.0 - smoothstep(0.55, 1.0, abs(angle) / ARC_END)
                    strength = band * arc_alpha * taper
                    if strength > 0:
                        tint = colours["arc"] if variant != "tinted" else MOON_COLOUR
                        colour = blend(colour, tint, strength)
                        alpha = max(alpha, strength)

            # --- Crescent ---------------------------------------------------
            inside = coverage_circle(u - moon_cx, v - moon_cy, MOON_RADIUS, feather)
            bitten = coverage_circle(u - bite_cx, v - bite_cy, BITE_RADIUS, feather)
            crescent = max(0.0, inside - bitten)

            if crescent > 0:
                colour = blend(colour, MOON_COLOUR, crescent)
                alpha = max(alpha, crescent)

            pixels.extend((*colour, round(alpha * 255)))

    return bytes(pixels)


def write_png(path: Path, rgba: bytes) -> None:
    """Minimal PNG writer — no third-party imaging dependency."""

    def chunk(kind: bytes, payload: bytes) -> bytes:
        return (
            struct.pack(">I", len(payload))
            + kind
            + payload
            + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)
        )

    stride = SIZE * 4
    # Filter byte 0 (None) per scanline: the artwork compresses well enough that
    # smarter filters would only add code to review.
    raw = b"".join(b"\x00" + rgba[y * stride:(y + 1) * stride] for y in range(SIZE))

    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


CONTENTS = """{
  "images" : [
    {
      "filename" : "icon-light.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "dark"
        }
      ],
      "filename" : "icon-dark.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    },
    {
      "appearances" : [
        {
          "appearance" : "luminosity",
          "value" : "tinted"
        }
      ],
      "filename" : "icon-tinted.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""


def main() -> int:
    for name, colours in VARIANTS.items():
        iconset = ASSETS / f"{name}.appiconset"
        iconset.mkdir(parents=True, exist_ok=True)

        for variant in ("light", "dark", "tinted"):
            write_png(iconset / f"icon-{variant}.png", render(variant, colours))

        (iconset / "Contents.json").write_text(CONTENTS, encoding="utf-8")
        print(f"  wrote {name}.appiconset")

    print(f"{len(VARIANTS)} icon variants written to {ASSETS.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
