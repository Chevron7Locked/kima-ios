#!/bin/bash
# Proves a test red: plants a mutant in production code, runs the tests, and puts the file back.
# Usage: scripts/mutant.sh <file> <old> <new> <test.sh args...>
#   e.g. scripts/mutant.sh Kima/Player/PlaybackEngine+Stall.swift 'isPlaying = false' 'isPlaying = true' \
#          '-only-testing:KimaTests/FLACSeekFallbackTests/testTheSwapsHeldPlayingEndsWhenTheSkipNeverPlays'
# <old> must occur exactly once in <file> (multi-line strings are fine). The file is restored
# byte-for-byte from a copy on any exit, interrupts included, so a dirty working copy (the usual
# state mid-TDD) comes back as it was.
# Exit: 0 killed (an XCTest assertion failed under the mutant), 1 survived (still green),
#       2 no verdict (usage, <old> not matched once, or a red without a test failure: a build
#       error or a simulator refusal, which proves nothing about the test).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 2

if [ $# -lt 4 ]; then
    echo "usage: scripts/mutant.sh <file> <old> <new> <test.sh args...>" >&2
    exit 2
fi
file=$1 old=$2 new=$3
shift 3
[ -f "$file" ] || { echo "mutant: no such file: $file" >&2; exit 2; }

backup=$(mktemp "${TMPDIR:-/tmp}/kima-mutant.XXXXXX") || exit 2
cp -p "$file" "$backup" || exit 2
restore() { cp -p "$backup" "$file" && rm -f "$backup"; }
trap restore EXIT
child=""
# An interrupt ends the run now (bash defers traps behind a foreground child, so the run waits in
# the background): stop test.sh and its xcodebuild, then exit; the EXIT trap restores.
trap '[ -n "$child" ] && { pkill -TERM -P "$child"; kill "$child"; } 2>/dev/null; exit 130' INT TERM

python3 -I -c '
import sys
path, old, new = sys.argv[1:4]
text = open(path).read()
n = text.count(old)
if n != 1:
    sys.exit(f"mutant: <old> occurs {n} times in {path}; it must occur exactly once")
open(path, "w").write(text.replace(old, new))
' "$file" "$old" "$new" || exit 2

echo "mutant planted in $file"
scripts/test.sh "$@" &
child=$!
wait "$child"
ec=$?
child=""
if [ "$ec" -eq 0 ]; then
    echo "SURVIVED: the tests stayed green under the mutant" >&2
    exit 1
fi
# A kill is an assertion failing, not any red: `File.swift:NN: error: -[Suite test] : reason`.
if grep -qE ':[0-9]+: error: -\[' build/last-test.log; then
    echo "KILLED: an assertion failed under the mutant (lines above)"
    exit 0
fi
echo "NO VERDICT: red without a test failure (test.sh exit $ec; build error or simulator?): build/last-test.log" >&2
exit 2
