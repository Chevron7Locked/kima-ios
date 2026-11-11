#!/bin/sh
# Advisory glossary-prose check (ticket-05 retro, Kevin 2026-11-11): a comment that says
# "main player" — GLOSSARY.md's term is main playback; its _Avoid_ list bans "'the player'
# when meaning main specifically", and "main player" is the one unambiguous prose spelling
# of that miss. Bare "the player" in comments mostly means the app or the player UI, so
# reviewers keep judging those; this script only catches what can never be right.
# Prose rulings live in GLOSSARY.md — this just moves detection from review to commit.
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

if [ -n "$hits" ]; then
    printf '%s\n%s\n' \
        'glossary-prose (advisory): a comment says "main player"; GLOSSARY.md calls it main playback:' \
        "$hits" >&2
fi
exit 0
