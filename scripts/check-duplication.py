#!/usr/bin/env python3
"""Deterministic duplication check: CODING_STANDARDS.md §Code smells — duplicated code is a
violation, not a judgement call. Two passes, both hard:

1. Blocks — maximal runs of MIN_LINES identical (after normalization) code lines shared by two
   places — different files, or the same file far enough apart.
2. Helpers — whole `func` definitions with the same name and identical normalized bodies, in
   two places regardless of length. A named helper copied verbatim can never be boilerplate;
   this is the shape a MIN_LINES block floor always misses (three copies of a 6-line waitUntil
   shipped past pass 1 before it earned pass 2).
3. Waits — pass 1 at MIN_WAIT_LINES, kept only when the block holds a wait (`waitUntil`,
   `Self.settle`) and pass 1 doesn't already report it. Short wait-then-assert sequences are the shape this repo keeps copying under
   the 8-line floor (ticket 25: a 4-line "skip, wait, wait, assert silent" copy shipped to review).

Normalization drops comments and indentation, so a copy with reworded comments still counts —
that is the shape of every violation this repo has actually shipped. Findings exit 1 with the
locations so the pre-commit hook refuses the commit.

Emergency skip stays the hook's own: git commit --no-verify
"""

import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCAN_DIRS = ["Kima", "KimaTests", "KimaUITests"]
MIN_LINES = 8        # normalized code lines shared verbatim; below this, boilerplate dominates
BOILERPLATE_CAP = 60  # a line in more files than this is Swift furniture, not duplication
MAX_OFFSETS = 4000   # safety cap on diagonals walked per pair
MIN_WAIT_LINES = 4   # pass 3's floor: a block this long counts only if it holds a wait
WAIT = re.compile(r"\bwaitUntil\b|\bSelf\.settle\b")   # `waitUntil {` (no args) counts too
MIN_HELPER_LINES = 3  # normalized lines a func must span to count as a helper, not a stub

# Known debt: copies that predate the helper pass, baselined like check-test-posture.py's —
# migrate them and shrink this list, never add to it. Entries are "file:funcName"; both sides
# of a finding must be listed for it to stay quiet (a new copy elsewhere still fires). The
# tearDown pair IS the debt check-test-posture.py already notes: migrating those suites to
# KeychainLoginTestCase deletes this entry by itself.
BASELINE = {
    "CredentialServerTests.swift:tearDown",
    "LaunchResumeTests.swift:tearDown",
}

COMMENT_STARTS = ("//", "/*", "*/", "*")
TRIVIAL = re.compile(r"^[\W_]*$")          # punctuation-only lines: braces, parens, commas
LINE_COMMENT = re.compile(r"(?<!:)//.*$")  # keep https:// intact
FUNC_SIG = re.compile(r"\bfunc\s+(\w+)\s*[(<]")


def normalize(raws):
    """Code-only, whitespace-stripped lines from raw source lines."""
    out = []
    for raw in raws:
        line = LINE_COMMENT.sub("", raw).strip()
        if not line or line.startswith(COMMENT_STARTS) or TRIVIAL.match(line):
            continue
        out.append(line)
    return out


def normalized_lines(path: Path):
    """Code-only, whitespace-stripped lines with their original line numbers."""
    out = []
    for no, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = LINE_COMMENT.sub("", raw).strip()
        if not line or line.startswith(COMMENT_STARTS) or TRIVIAL.match(line):
            continue
        out.append((no, line))
    return out


def func_defs(path: Path):
    """Every `func` with a brace-balanced body: (name, start line 1-based, normalized body)."""
    raws = path.read_text(encoding="utf-8").splitlines()
    defs = []
    i = 0
    while i < len(raws):
        stripped = raws[i].strip()
        m = None if stripped.startswith(COMMENT_STARTS) else FUNC_SIG.search(raws[i])
        if m:
            depth, opened, j = 0, False, i
            while j < len(raws):
                for ch in raws[j]:
                    if ch == "{":
                        depth, opened = depth + 1, True
                    elif ch == "}":
                        depth -= 1
                if opened and depth <= 0:
                    break
                j += 1
            if opened and depth <= 0:
                body = normalize(raws[i:j + 1])
                if len(body) >= MIN_HELPER_LINES:
                    defs.append((m.group(1), i + 1, tuple(body)))
                i = j + 1
                continue
        i += 1
    return defs


def identical_helpers(files, rel_of):
    """(findings, baselined notes) for funcs whose name and normalized body match verbatim
    across two places."""
    by_key = defaultdict(lambda: defaultdict(list))  # (name, body) -> file -> [start lines]
    notes = []
    for fi, path in enumerate(files):
        for name, start, body in func_defs(path):
            by_key[(name, body)][fi].append(start)
    findings = []
    for (name, _), per_file in sorted(by_key.items()):
        if len(per_file) > BOILERPLATE_CAP:
            continue
        places = [(rel_of[fi], no) for fi in sorted(per_file) for no in sorted(per_file[fi])]
        if len({(f, no) for f, no in places}) < 2:
            continue   # a lone definition (or one file's repeats handled by the block pass)
        live = [p for p in places if f"{Path(p[0]).name}:{name}" not in BASELINE]
        if live:   # fully baselined stays quiet; one new copy beside the debt still fires
            findings.append((name, places))   # show every place, baselined included, for context
        else:
            notes.append((name, places))
    return findings, notes


def common_run(a, b, offset, i, min_len):
    """Length of the equal-token run starting at a[i] vs b[i+offset]."""
    n = 0
    limit = min(len(a), len(b) - offset)
    while i + n < limit and a[i + n] == b[i + offset + n]:
        n += 1
    return n if n >= min_len else 0


def runs_on_diagonal(a, b, offset, min_len):
    """All maximal equal runs of >= min_len along b[i+offset] == a[i]."""
    found = []
    i = max(0, -offset)
    limit = min(len(a), len(b) - offset)
    while i < limit:
        n = common_run(a, b, offset, i, min_len)
        if n:
            found.append((i, n))
            i += n
        else:
            i += 1
    return found


def place(lines, index, length):
    return (lines[index][0], lines[min(index + length - 1, len(lines) - 1)][0])


def duplicated_blocks(code, min_len, keep=lambda lines, pair: True):
    """Merged pairs of places sharing a maximal run of >= min_len identical normalized lines;
    `keep` filters each run, by its lines and its pair of places, before any merging."""
    # Intern lines to ints; index line -> files, and line -> positions per file.
    ids = {}
    tokens = []
    owners = defaultdict(set)
    positions = defaultdict(lambda: defaultdict(list))  # token -> file -> [index]
    for fi, lines in enumerate(code):
        toks = []
        for idx, (_, line) in enumerate(lines):
            if line not in ids:
                ids[line] = len(ids)
            t = ids[line]
            toks.append(t)
            owners[t].add(fi)
            positions[t][fi].append(idx)
        tokens.append(toks)

    # Candidate file pairs: those sharing at least min_len distinct non-boilerplate lines.
    shared = defaultdict(set)  # (fi, fj) -> {token}
    for t, fs in owners.items():
        fs = sorted(fs)
        if len(fs) > BOILERPLATE_CAP:
            continue
        for x in range(len(fs)):
            for y in range(x + 1, len(fs)):
                shared[(fs[x], fs[y])].add(t)

    findings = set()

    def add(fi, start, fj, start_j, length):
        pair = ((fi,) + place(code[fi], start, length), (fj,) + place(code[fj], start_j, length))
        if keep([ln for _, ln in code[fi][start:start + length]], pair):
            findings.add(pair)

    # Same-file pass: a region repeated within one file (offset keeps it from matching
    # itself or its near neighbours).
    for fi, toks in enumerate(tokens):
        local = defaultdict(list)
        for idx, t in enumerate(toks):
            local[t].append(idx)
        offsets = set()
        for pos in local.values():
            for ta in pos:
                for tb in pos:
                    if tb - ta >= min_len * 2:
                        offsets.add(tb - ta)
                    if len(offsets) > MAX_OFFSETS:
                        break
        for offset in offsets:
            for start, length in runs_on_diagonal(toks, toks, offset, min_len):
                add(fi, start, fi, start + offset, length)

    for (fi, fj), toks in shared.items():
        if len(toks) < min_len:
            continue
        a, b = tokens[fi], tokens[fj]
        offsets = set()
        for t in toks:
            for ta in positions[t][fi]:
                for tb in positions[t][fj]:
                    off = tb - ta
                    if fi == fj and off < min_len * 2:
                        continue  # same-file matches only when the regions are apart
                    offsets.add(off)
                    if len(offsets) > MAX_OFFSETS:
                        break
            if len(offsets) > MAX_OFFSETS:
                break
        for offset in offsets:
            for start, length in runs_on_diagonal(a, b, offset, min_len):
                add(fi, start, fj, start + offset, length)

    return _merge(findings, min_len) if findings else []


def wait_sequences(code, blocks):
    """Pass 3: runs of MIN_WAIT_LINES+ holding a wait, minus runs inside a pass-1 block. The
    covered runs drop before merging, so one can't widen a neighbouring short run into a
    region that repeats pass 1's report."""
    return duplicated_blocks(code, MIN_WAIT_LINES, lambda lines, pair: (
        any(WAIT.search(ln) for ln in lines) and not any(_within(pair, b) for b in blocks)))


def main():
    files = sorted(p for d in SCAN_DIRS for p in (ROOT / d).rglob("*.swift"))
    rel_of = [str(p.relative_to(ROOT)) for p in files]
    code = [normalized_lines(p) for p in files]

    findings = duplicated_blocks(code, MIN_LINES)
    wait_findings = wait_sequences(code, findings)

    helpers, debt_notes = identical_helpers(files, rel_of)
    for name, places in debt_notes:
        print(f"known debt (baselined, do not add): func {name} at "
              + ", ".join(f"{f}:{no}" for f, no in places))

    if not findings and not helpers and not wait_findings:
        print(f"no duplicated blocks ({MIN_LINES}+ identical code lines, {MIN_WAIT_LINES}+ with a "
              f"wait) and no identical helper definitions across {len(files)} files in "
              f"{'/'.join(SCAN_DIRS)}")
        return 0

    print("duplicated code is a violation, not a judgement call "
          "(CODING_STANDARDS.md §Code smells):")
    for pairs, what in ((findings, "duplicated block(s)"),
                        (wait_findings, f"duplicated wait sequence(s) ({MIN_WAIT_LINES}+ lines holding a wait)")):
        if pairs:
            print(f"  {len(pairs)} {what}:")
            for (fi, s1, e1), (fj, s2, e2) in sorted(pairs):
                print(f"    {rel_of[fi]}:{s1}-{e1}, {rel_of[fj]}:{s2}-{e2}")
    if helpers:
        print(f"  {len(helpers)} identical helper definition(s) (same name and body, any length):")
        for name, places in helpers:
            print(f"    func {name}: " + ", ".join(f"{f}:{no}" for f, no in places))
    print("\nExtract the shape; keep only the data difference at each call site.")
    return 1


def _merge(findings, min_len):
    """A block whose tail continues on a neighbouring diagonal is one region: merge pairs
    whose places in the same file touch or overlap (gap under min_len)."""
    merged = [list(f) for f in findings]
    changed = True
    while changed:
        changed = False
        out = []
        while merged:
            cur = merged.pop()
            rest = []
            for other in merged:
                if _adjacent(cur, other, min_len):
                    cur = _union(cur, other)
                    changed = True
                else:
                    rest.append(other)
            merged = rest
            out.append(cur)
        merged = out
    return [tuple(sorted(f)) for f in merged]


def _adjacent(a, b, min_len):
    for (fa, sa, ea) in a:
        for (fb, sb, _) in b:
            if fa == fb and sa - min_len <= sb <= ea + min_len:
                return True
    return False


def _within(a, b):
    """Every place of `a` lies inside a place of `b` in the same file."""
    return all(any(fa == fb and sb <= sa and ea <= eb for fb, sb, eb in b) for fa, sa, ea in a)


def _union(a, b):
    spans = {}
    for f, s, e in a + b:
        s0, e0 = spans.get(f, (s, e))
        spans[f] = (min(s0, s), max(e0, e))
    return [(f, s, e) for f, (s, e) in spans.items()]


if __name__ == "__main__":
    sys.exit(main())
