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

# Scope honesty: bare invocation is the whole scheme — KimaUITests ride along, and many of
# those classes need production :3030. When UI tests are in scope, probe :3030 up front so a
# red can be classified BEFORE the run rather than after 40 minutes of it: while prod is
# down, data-backed classes fail environmentally, not as regressions (CLAUDE.md §Server contract).
if printf '%s\n' "$@" | grep -q -- '-only-testing:'; then
    ui_in_scope=$(printf '%s\n' "$@" | grep -qi -- 'KimaUITests' && echo 1 || echo 0)
else
    echo "scope: FULL SCHEME — KimaUITests included (many need prod :3030); unit-only: -only-testing:KimaTests"
    ui_in_scope=1
fi
if [ "$ui_in_scope" = 1 ]; then
    if curl -so /dev/null --connect-timeout 5 "${KIMA_PROD_URL:-https://listen.chevron7.io:3030}/api/health"; then
        echo "prod :3030: up"
    else
        echo "WARNING: prod :3030 unreachable — data-backed KimaUITests classes will fail environmentally, not as regressions" >&2
    fi
fi

UDID=${KIMA_TEST_UDID:-$(sed -nE 's/.*id=([0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}).*/\1/p' .git/hooks/pre-commit | head -1)}
if [ -z "$UDID" ]; then
    echo "no simulator UDID: pin one in .git/hooks/pre-commit or set KIMA_TEST_UDID" >&2
    exit 2
fi

LOG=$(mktemp "${TMPDIR:-/tmp}/kima-test.XXXXXX") || exit 2
echo "full log: $LOG (destination id=$UDID)"
# Stable pointer for post-mortems: mktemp paths under $TMPDIR are unguessable; build/ is gitignored.
mkdir -p build && ln -sfn "$LOG" build/last-test.log || true

# The transcript goes to $LOG, never stdout: a full run is ~100KB, and an agent that pipes
# that away to save context loses the exit code with it. Green prints one count line;
# red prints its own failure tail below. Read $LOG (also build/last-test.log) for the transcript.
xcodebuild -project Kima.xcodeproj -scheme Kima \
    -destination "platform=iOS Simulator,id=$UDID" \
    test "$@" >"$LOG" 2>&1
status=$?

if grep -q '\*\* TEST SUCCEEDED \*\*' "$LOG" && grep -qE 'Executed [1-9][0-9]* tests?' "$LOG"; then
    echo "green: $(grep -oE 'Executed [0-9]+ tests?, with [0-9]+ failures?' "$LOG" | tail -1)"
    exit 0
fi
echo "not green (xcodebuild exit $status):" >&2
grep -E '\*\* TEST (SUCCEEDED|FAILED) \*\*|Executed [0-9]+ tests?' "$LOG" | tail -4 >&2
# Per-test failure messages: XCTest emits `File.swift:NN: error: -[Suite test] : reason`.
# The summary above buries them when a class fails en masse — print them whole (capped)
# so a red needs no xcresulttool dig.
grep -E 'error:' "$LOG" | head -40 >&2
# Non-test reds read like test failures; name them when the log shows them.
if grep -qE "failed preflight checks|Simulator device failed to launch" "$LOG"; then
    echo "hint: simulator refused the launch (often 'Busy' after an earlier hung run): xcrun simctl shutdown $UDID 2>/dev/null; xcrun simctl bootstatus $UDID -b, then rerun" >&2
fi
if grep -q "Restarting after unexpected exit, crash, or test timeout" "$LOG"; then
    echo "hint: the runner restarted mid-run — classes before that marker may not have rerun; the blamed test hung or crashed rather than failed" >&2
fi
# A test that started and never printed a result is the hang itself (key on the quoted
# identifier: the class-space-method name means $3 alone is shared across a whole class).
hung=$(awk '/Test Case \047/ { id = $0; sub(/^Test Case \047/, "", id); sub(/\047.*$/, "", id)
     if ($0 ~ /started\./) t[id] = 1; else delete t[id] } END { for (n in t) print "  " n }' "$LOG")
if [ -n "$hung" ]; then
    echo "hint: no result ever printed for these — an unbounded wait hung the runner (polling waits ride waitUntil, KimaTests/Support):" >&2
    printf '%s\n' "$hung" >&2
fi
[ "$status" -ne 0 ] && exit "$status"
exit 1
