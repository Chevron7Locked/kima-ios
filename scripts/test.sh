#!/bin/bash
# Kima test runner with an honest exit code. Filtered xcodebuild output lies — a
# `| grep` pipeline exits 0 on ** TEST FAILED **, and zero matched tests still print
# ** TEST SUCCEEDED ** ("Executed 0 tests"). So green here means: xcodebuild exited 0,
# the log says ** TEST SUCCEEDED **, AND at least one test actually executed.
# Usage: scripts/test.sh [-only-testing:KimaTests/<Class> ...]
# Destination: the UDID pinned by .git/hooks/pre-commit (xcodebuild boots it itself);
# override with KIMA_TEST_UDID=<udid> (xcrun simctl list devices available).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

UDID=${KIMA_TEST_UDID:-$(sed -nE 's/.*id=([0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}).*/\1/p' .git/hooks/pre-commit | head -1)}
if [ -z "$UDID" ]; then
    echo "no simulator UDID: pin one in .git/hooks/pre-commit or set KIMA_TEST_UDID" >&2
    exit 2
fi

LOG=$(mktemp "${TMPDIR:-/tmp}/kima-test.XXXXXX") || exit 2
echo "full log: $LOG (destination id=$UDID)"

xcodebuild -project Kima.xcodeproj -scheme Kima \
    -destination "platform=iOS Simulator,id=$UDID" \
    test "$@" 2>&1 | tee "$LOG"
status=${PIPESTATUS[0]}

if grep -q '\*\* TEST SUCCEEDED \*\*' "$LOG" && grep -qE 'Executed [1-9][0-9]* tests?' "$LOG"; then
    exit 0
fi
echo "not green (xcodebuild exit $status):" >&2
grep -E '\*\* TEST (SUCCEEDED|FAILED) \*\*|Executed [0-9]+ tests?|error:' "$LOG" | tail -5 >&2
[ "$status" -ne 0 ] && exit "$status"
exit 1
