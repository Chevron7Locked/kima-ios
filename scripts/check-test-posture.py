#!/usr/bin/env python3
"""Kima test-posture guardrail: shared postures ride, they don't copy — and polling waits
carry a deadline. Two guards:

1. Login-writing suites. CLAUDE.md §Build says look in KimaTests/Support/ before writing
another setUp posture; ticket 12's review found a suite hand-rolling exactly what
KeychainLoginTestCase carries (snapshot the login, hard-assert writability, clearCredentials,
restore). That copy survives check-duplication.py because semantic copying needs no byte
identity — so this is its proxy: a test file outside Support/ that re-implements the
writability-probe posture (KeychainLoginSnapshot + the probe credential) must declare
`: KeychainLoginTestCase`. Per-test fixtures are NOT violations: snapshotting around a
single write with `defer` (KimaAPIClientTests, StreamTicketTests) is what
KeychainLoginSnapshot exists for; only the suite-level ritual fires.

2. Unbounded poll loops. A `while <condition> { await Task.yield() }` has no deadline: when
the condition stalls it hangs the runner, and xcodebuild blames the class with no result —
one full-suite run went to log forensics over exactly this (ticket 15 close-out). Support's
waitUntil polls with a deadline; its contract is to assert the fact after waiting. The proxy
is the shape: a `while` line yielding on the same or next line. A lone `await Task.yield()`
(one-shot main-actor flush) stays legal.

Each guard's BASELINE lists pre-existing offenders; migrate them and shrink the lists —
never add to it. Exit 0 = clean (baseline noted), 1 = a new offender. Stdlib-only, fast.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent / "KimaTests"
SUPPORT = ROOT / "Support"

BASELINE = {
    # Known debt: full ritual re-implemented before this check landed — migrate to
    # KeychainLoginTestCase (its quiesce() hook covers loop-stopping suites) and remove here.
    "LaunchResumeTests.swift",
    "CredentialServerTests.swift",
}

RITUAL = re.compile(r'KeychainStore\.setCredential\(\s*"probe"')
SUBCLASS = re.compile(r':\s*KeychainLoginTestCase\b')

POLLS_BASELINE: set[str] = set()   # shrink-only, like BASELINE
# `while !Task.isCancelled` is excluded: cancellation IS its deadline — the cooperative-cancel
# idiom production's keeper loops use, not a poll on external state.
POLL_INLINE = re.compile(r"\bwhile\b(?!.*!Task\.isCancelled).*Task\.yield\s*\(\s*\)")
POLL_OPENER = re.compile(r"\bwhile\b(?!.*!Task\.isCancelled).*\{\s*$")


def poll_sites(path):
    """1-based lines where a while-loop hand-spins on Task.yield(): inline, or the
    yield sitting on the line after an opener."""
    lines = path.read_text(encoding="utf-8").splitlines()
    sites = []
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("//"):
            continue
        if POLL_INLINE.search(line) or (POLL_OPENER.search(line)
                                        and i + 1 < len(lines)
                                        and "Task.yield()" in lines[i + 1]):
            sites.append(i + 1)
    return sites


def main() -> int:
    offenders, baselined, poll_offenders = [], [], []
    for path in sorted(ROOT.rglob("*.swift")):
        if SUPPORT in path.parents or path.name == "check-test-posture.py":
            continue
        text = path.read_text(encoding="utf-8")
        if "KeychainLoginSnapshot" not in text or not RITUAL.search(text):
            continue
        if SUBCLASS.search(text):
            continue
        (baselined if path.name in BASELINE else offenders).append(path)

    for path in sorted(ROOT.rglob("*.swift")):
        if SUPPORT in path.parents:
            continue
        sites = poll_sites(path)
        if not sites:
            continue
        if path.name in POLLS_BASELINE:
            print(f"known debt (baselined, do not add): {path.relative_to(ROOT.parent)} "
                  f"spins without a deadline at line(s) {', '.join(map(str, sites))}")
        else:
            poll_offenders.append((path, sites))

    for path in baselined:
        print(f"known debt (baselined, do not add): {path.relative_to(ROOT.parent)} "
              f"re-implements the KeychainLoginTestCase posture")
    if offenders:
        print("posture violation: this suite re-implements what KimaTests/Support/"
              "KeychainLoginTestCase.swift carries (snapshot login, hard-assert writability, "
              "clearCredentials, restore) — subclass it instead:", file=sys.stderr)
        for path in offenders:
            print(f"  {path.relative_to(ROOT.parent)}", file=sys.stderr)
    if poll_offenders:
        print("posture violation: this while-loop polls with no deadline — when the condition "
              "stalls it hangs the runner and xcodebuild blames the class. Ride waitUntil "
              "(KimaTests/Support/WaitUntil.swift, 2 s deadline) and assert the fact after:",
              file=sys.stderr)
        for path, sites in poll_offenders:
            print(f"  {path.relative_to(ROOT.parent)}:{', '.join(map(str, sites))}", file=sys.stderr)
    if offenders or poll_offenders:
        return 1
    return 0

if __name__ == "__main__":
    sys.exit(main())
