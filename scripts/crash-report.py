#!/usr/bin/env python3
"""Names the crashes a test run caused, read from macOS's own crash reports.

A crash in the app or test host only shows in the xcodebuild log as "Restarting after
unexpected exit, crash, or test timeout": no reason, no frame. The reason lands in
~/Library/Logs/DiagnosticReports/<process>-<time>.ips instead (ticket 30 retro: a mutant's
index-out-of-range trap read as a hang until that file was opened by hand).

Usage: scripts/crash-report.py <since-file> <simulator-udid>
  Reports every .ips newer than <since-file> whose process ran on that simulator, one line each:
    crash: <exception> (<signal>) in <first app frame> (<file:line>), test <test frame> - <ips path>
Exit: 0 one or more crashes reported, 1 none. Stdlib-only.
"""
import json
import pathlib
import sys

REPORTS = pathlib.Path.home() / "Library/Logs/DiagnosticReports"
# Frames from these images are the runtime, not the code under test: the first frame outside
# them is where the crash is the app's or the test's own doing.
SYSTEM_IMAGE_PREFIXES = ("libswift", "libsystem", "libdispatch", "libobjc", "dyld", "XCTest",
                         "CoreFoundation", "Foundation", "UIKit", "SwiftUI")


def frame_text(frame, images):
    image = images[frame["imageIndex"]].get("name", "?") if "imageIndex" in frame else "?"
    symbol = frame.get("symbol", "?")
    where = f" ({frame['sourceFile']}:{frame['sourceLine']})" if "sourceFile" in frame and "sourceLine" in frame else ""
    return image, symbol + where


def load(path):
    """The report body; line 1 is a header object, the rest the report (slashes JSON-escaped)."""
    header, body = path.read_text().split("\n", 1)
    json.loads(header)
    return json.loads(body)


def describe(path, report):
    exception = report.get("exception", {})
    images = report.get("usedImages", [])
    threads = [t for t in report.get("threads", []) if t.get("triggered")]
    frames = [frame_text(f, images) for f in (threads[0]["frames"] if threads else [])]
    app = next((text for image, text in frames if not image.startswith(SYSTEM_IMAGE_PREFIXES) and image != "?"), "?")
    test = next((text for image, text in frames if image.endswith("Tests") and ".test" in text), None)
    line = f"crash: {exception.get('type', '?')} ({exception.get('signal', '?')}) in {app}"
    if test and test != app:
        line += f", test {test}"
    return line + f" - {path}"


def main():
    if len(sys.argv) != 3:
        print("usage: scripts/crash-report.py <since-file> <simulator-udid>", file=sys.stderr)
        return 2
    since = pathlib.Path(sys.argv[1]).stat().st_mtime
    udid = sys.argv[2]
    found = 0
    for path in sorted(REPORTS.glob("*.ips"), key=lambda p: p.stat().st_mtime):
        if path.stat().st_mtime <= since:
            continue
        try:
            report = load(path)
            if f"/Devices/{udid}/" not in report.get("procPath", ""):
                continue
            print(describe(path, report))
            found += 1
        except (OSError, ValueError, KeyError, IndexError):
            continue   # a report still being written, or not a process crash: not this run's
    return 0 if found else 1


if __name__ == "__main__":
    sys.exit(main())
