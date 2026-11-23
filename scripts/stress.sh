#!/bin/bash
# Reproduces a flake that passes alone but fails under full-suite load: runs scripts/test.sh with
# -test-iterations while busy-loop processes hog the CPU, then counts each failing test.
# Usage: N=40 STRESS=24 scripts/stress.sh '-only-testing:KimaTests/<Class>/<test>' [more test.sh args]
#   N       iterations (default 20)
#   STRESS  busy-loop processes (default twice the core count; 0 runs unloaded)
# Exit: test.sh's (0 = every iteration green). The full log is build/last-test.log.
#
# Before believing a 0-failure run, get a red rate first (ticket 27: 2/40 before the fix). Heavy
# instrumentation can hide the race it's meant to catch: full KVO logging with stack captures went
# 0/200, and logging only the transitions brought it back at 4/150. Log the transitions only.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 2
[ $# -gt 0 ] || { sed -n '2,6p' "$0" >&2; exit 2; }

N=${N:-20}
STRESS=${STRESS:-$(( $(sysctl -n hw.ncpu) * 2 ))}
pids=()
for _ in $(seq 1 "$STRESS"); do yes >/dev/null & pids+=($!); done
trap '[ ${#pids[@]} -eq 0 ] || kill "${pids[@]}" 2>/dev/null' EXIT

echo "stress: $N iteration(s), $STRESS busy process(es)"
scripts/test.sh "$@" -test-iterations "$N"; ec=$?

echo "stress: failing tests (failure lines per test):"
grep ': error: -\[' build/last-test.log | grep -oE '\[[A-Za-z0-9_.]+ test[A-Za-z0-9_]+\]' \
    | sort | uniq -c | sort -rn | grep . || echo "  none"
exit $ec
