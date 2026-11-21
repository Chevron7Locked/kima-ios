#!/bin/bash
# The green-tree record: lets the pre-commit hook skip rerunning KimaTests on a tree that
# scripts/test.sh just ran green, whole target. One owner for the record's path and its tree.
#
#   fingerprint     print the working copy's tree: tracked + untracked, ignored/excluded out
#   record <tree>   save <tree> as green (test.sh, after a whole-KimaTests green)
#   clear           forget any record (test.sh, before a whole-KimaTests run)
#   matches-staged  exit 0 when the tree being committed is the recorded green tree (the hook)
#
# Any difference between what was tested and what is committed (a partial stage, an edit since
# the run, an unstaged new file) gives a different tree, so the hook runs the suite as before.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 2
RECORD=build/kimatests-green-tree

case "${1:-}" in
fingerprint)
    # A scratch copy of the index, so the real one is never touched.
    tmp_index=$(mktemp "${TMPDIR:-/tmp}/kima-index.XXXXXX") || exit 2
    trap 'rm -f "$tmp_index"' EXIT
    cp "$(git rev-parse --git-path index)" "$tmp_index" || exit 2
    GIT_INDEX_FILE="$tmp_index" git add -A || exit 2
    GIT_INDEX_FILE="$tmp_index" git write-tree
    ;;
record)
    [ -n "${2:-}" ] || exit 2
    mkdir -p build && echo "$2" > "$RECORD"
    ;;
clear)
    rm -f "$RECORD"
    ;;
matches-staged)
    # git write-tree reads $GIT_INDEX_FILE when git sets it (commit -a, commit <paths>).
    recorded=$(cat "$RECORD" 2>/dev/null) || exit 1
    [ -n "$recorded" ] && [ "$recorded" = "$(git write-tree)" ]
    ;;
*)
    echo "usage: $0 fingerprint | record <tree> | clear | matches-staged" >&2
    exit 2
    ;;
esac
