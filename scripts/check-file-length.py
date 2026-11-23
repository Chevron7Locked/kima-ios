#!/usr/bin/env python3
"""Kima file-length guardrail: a Swift file stays at or under LIMIT lines.

CLAUDE.md §Code set "about 350 lines max per Swift file" as prose, so reviewers
measured it by hand: both ticket-27 Standards passes spent words on
PlaybackEngine.swift's headroom. A line count is mechanical, so it's a check.
Over the limit: split it into subviews or extensions.

BASELINE holds files already over the limit, each with its count when it was
added: one of them may not grow past that count, and it leaves the list once it
is split under LIMIT. Shrink the list and never add to it. Exit 0 = clean
(baseline noted), 1 = a new offender or a baselined file grown. Stdlib-only, fast.
"""
import pathlib
import subprocess
import sys

LIMIT = 350
BASELINE = {
    "Kima/Player/PlaybackController.swift": 357,
    "Kima/Player/QueueSheet.swift": 352,
}

root = pathlib.Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
failures, noted = [], []
for top in ("Kima", "KimaTests", "KimaUITests"):
    for path in sorted((root / top).rglob("*.swift")):
        rel = path.relative_to(root).as_posix()
        lines = len(path.read_text(encoding="utf-8").splitlines())
        cap = BASELINE.get(rel)
        if cap is not None:
            if lines > cap:
                failures.append(f"{rel}: {lines} lines, grown past its baseline {cap}")
            elif lines > LIMIT:
                noted.append(f"{rel} ({lines})")
        elif lines > LIMIT:
            failures.append(f"{rel}: {lines} lines (limit {LIMIT}): split into subviews or extensions")

stale = [rel for rel in BASELINE if (root / rel).exists()
         and len((root / rel).read_text(encoding="utf-8").splitlines()) <= LIMIT]
for rel in stale:
    print(f"file length: {rel} is under {LIMIT} now; drop it from BASELINE")

if failures:
    print("file length over the limit:", *failures, sep="\n  ", file=sys.stderr)
    sys.exit(1)
print(f"file length: every Swift file within {LIMIT} lines"
      + (f"; baselined: {', '.join(noted)}" if noted else ""))
