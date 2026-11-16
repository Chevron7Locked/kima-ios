#!/usr/bin/env python3
"""Kima artwork-tile guardrail: the named tile rides, it doesn't re-spell.

Ticket 20 named the app's most-repeated visual — clip to a continuous rounded
rect + 1pt KimaColor.hairline overlay — as `.kimaArtworkTile(cornerRadius:)`
(Kima/DesignSystem/KimaArtworkTile.swift). The pair had accumulated to 71
hand-spelled sites because nothing ever flagged it: five lines sit under
check-duplication.py's eight-line floor by design. This is the mechanical check
that floor cannot be: a `clipShape(RoundedRectangle` whose hairline strokeBorder
lands within the next few lines is the pair spelled by hand.

Artwork tiles call the primitive. Non-artwork plates (composed card surfaces,
the mini-player shell, the documented 0.5pt sleeve) legitimately clip content
and stroke the same shape; they sit in BASELINE with their reason — migrate or
justify, and shrink the list. Never add to it without a one-line why.

Exit 0 = clean (baseline noted), 1 = a new hand-spelled pair. Stdlib-only, fast.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / "Kima"

# The named owner spells the pair once, on purpose.
EXEMPT = {ROOT / "DesignSystem" / "KimaArtworkTile.swift"}

BASELINE = {
    # Pre-existing non-artwork plates: they clip composited card content, not
    # artwork, at KimaRadius.card or their own radius. Keep them here with the
    # reason; a new entry needs its one-line why.
    "DesignSystem/PaletteBackdropGradient.swift":  "palette plate (card radius, composed gradient content)",
    "Features/Home/VibeMapHero.swift":             "home card plate (star field + text, not artwork)",
    "Features/Radio/RadioViewComponents.swift":    "radio dialog plate (padded surface, not artwork)",
    "Player/MiniPlayerBar.swift":                  "mini-player card shell (chrome, not artwork)",
    "Player/PlayerSharedViews.swift":              "deliberate 0.5pt sleeve frame — documented treatment",
}

CLIP = re.compile(r"clipShape\(RoundedRectangle")
HAIRLINE = re.compile(r"strokeBorder\(KimaColor\.hairline")
WINDOW = 8  # lines after the clip in which the stroke still reads as the pair


def main() -> int:
    offenders = []
    hits = 0
    for path in sorted(ROOT.rglob("*.swift")):
        if path in EXEMPT:
            continue
        rel = str(path.relative_to(ROOT))
        lines = path.read_text(encoding="utf-8").splitlines()
        for i, line in enumerate(lines):
            if not CLIP.search(line):
                continue
            window = lines[i:i + WINDOW + 1]
            stroke = next((j for j in range(1, len(window)) if HAIRLINE.search(window[j])), None)
            if stroke is None:
                continue
            hits += 1
            if rel not in BASELINE:
                offenders.append(f"Kima/{rel}:{i + 1} clipShape + hairline strokeBorder "
                                 f"(+{stroke} lines) — use .kimaArtworkTile(cornerRadius:)")

    for o in offenders:
        print(o)
    if offenders:
        print(f"\nhand-spelled artwork tile: {len(offenders)} new site(s). "
              "The pair has a name — `.kimaArtworkTile()` (Kima/DesignSystem/KimaArtworkTile.swift); "
              "a genuinely non-artwork plate joins BASELINE with its reason.", file=sys.stderr)
        return 1

    print(f"artwork tiles clean: {hits} baselined plate(s), no hand-spelled pairs outside the primitive")
    return 0


if __name__ == "__main__":
    sys.exit(main())
