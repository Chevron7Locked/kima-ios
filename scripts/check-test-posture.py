#!/usr/bin/env python3
"""Kima guardrail: suites that write real logins ride the shared posture, they don't copy it.

CLAUDE.md §Build says look in KimaTests/Support/ before writing another setUp posture;
ticket 12's review found a suite hand-rolling exactly what KeychainLoginTestCase carries
(snapshot the login, hard-assert writability, clearCredentials, restore). That copy survives
check-duplication.py because semantic copying needs no byte identity — so this is its proxy:
a test file outside Support/ that re-implements the writability-probe posture
(KeychainLoginSnapshot + the probe credential) must declare `: KeychainLoginTestCase`.

Per-test fixtures are NOT violations: snapshotting around a single write with `defer`
(KimaAPIClientTests, StreamTicketTests) is what KeychainLoginSnapshot exists for; only the
suite-level snapshot-probe-clear-restore ritual fires. The BASELINE lists suites that
re-implemented the ritual before this check existed; migrate them and shrink the list —
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

def main() -> int:
    offenders, baselined = [], []
    for path in sorted(ROOT.rglob("*.swift")):
        if SUPPORT in path.parents or path.name == "check-test-posture.py":
            continue
        text = path.read_text(encoding="utf-8")
        if "KeychainLoginSnapshot" not in text or not RITUAL.search(text):
            continue
        if SUBCLASS.search(text):
            continue
        (baselined if path.name in BASELINE else offenders).append(path)

    for path in baselined:
        print(f"known debt (baselined, do not add): {path.relative_to(ROOT.parent)} "
              f"re-implements the KeychainLoginTestCase posture")
    if offenders:
        print("posture violation: this suite re-implements what KimaTests/Support/"
              "KeychainLoginTestCase.swift carries (snapshot login, hard-assert writability, "
              "clearCredentials, restore) — subclass it instead:", file=sys.stderr)
        for path in offenders:
            print(f"  {path.relative_to(ROOT.parent)}", file=sys.stderr)
        return 1
    return 0

if __name__ == "__main__":
    sys.exit(main())
