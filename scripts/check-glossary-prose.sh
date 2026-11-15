#!/bin/sh
# Advisory glossary-prose check (ticket-05 retro, Kevin 2026-11-11; extended ticket-06 retro):
# the greppable spellings of GLOSSARY.md rulings, moved from review to commit. Two checks:
# 1. A comment that says "main player" — GLOSSARY.md's term is main playback; its _Avoid_ list
#    bans "'the player' when meaning main specifically", and "main player" is the one
#    unambiguous prose spelling of that miss. Bare "the player" in comments mostly means the
#    app or the player UI, so reviewers keep judging those; this script only catches what can
#    never be right.
# 2. A let/var named isPlaying* assigned from an audible body inside Kima/Features/ — GLOSSARY
#    calls that state audible (§Glossary-name-sync's mechanical spelling: the sweeps have
#    renamed this pattern three times). Component parameters and `isPlaying:` labels carry a
#    flag someone else computed; those stay reviewer judgement, so only derivations hit.
# Advisory: prints hits to stderr, always exits 0.
# Usage: check-glossary-prose.sh [file...] — with no args, checks the staged .swift files.
set -u

if [ "$#" -gt 0 ]; then
    files=$(printf '%s\n' "$@")
else
    files=$(git diff --cached --name-only --diff-filter=ACMR | grep '\.swift$' || true)
fi
[ -z "${files:-}" ] && exit 0

hits=$(printf '%s\n' "$files" | while IFS= read -r f; do
    [ -f "$f" ] || continue
    grep -nE '(///|//)' "$f" | grep -iE '[[:<:]]main player[[:>:]]' | sed "s|^|$f:|" || true
done)

# (grep filter, not a case: bash 3.2 — the macOS /bin/sh — closes $( ) early on a case pattern's paren)
feat_files=$(printf '%s\n' "$files" | grep -E '(^|/)Kima/Features/' || true)

audible_hits=$(printf '%s\n' "$feat_files" | while IFS= read -r f; do
    [ -f "$f" ] || continue
    grep -nE '(let|var)[[:space:]]+isPlaying' "$f" | grep -E '=[^=]' \
        | grep -iE 'audible|isWaitingForAudio' | sed "s|^|$f:|" || true
done)

if [ -n "$hits" ]; then
    printf '%s\n%s\n' \
        'glossary-prose (advisory): a comment says "main player"; GLOSSARY.md calls it main playback:' \
        "$hits" >&2
fi
if [ -n "$audible_hits" ]; then
    printf '%s\n%s\n' \
        'glossary-prose (advisory): isPlaying assigned from an audible body; GLOSSARY.md names that state audible:' \
        "$audible_hits" >&2
fi
exit 0
