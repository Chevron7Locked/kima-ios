#!/usr/bin/env python3
"""Regenerate docs/api-endpoints.md from the kima-hub backend (the live TS contract).

Extraction: (1) router mounts in backend/src/index.ts, (2) every
router.<get|post|put|patch|delete>("<path>") in backend/src/routes/**/*.ts.
Path params are normalized to :param. Output is deterministic (sorted per
domain) so diffs show only real contract changes.

A file's URL prefix comes from the import graph, not from its file name.
`routes/library/artists.ts` is mounted by `routes/library/index.ts`
(`router.use(artistsRouter)`, no sub-path), which `index.ts` mounts at
`/api/library`, so its routes live at `/api/library/artists/...`. Route
paths follow the mount chain, never a file's stem: `artistsRoutes` is
imported from `routes/artists.ts`, a different file.

Usage: python3 scripts/extract-api-endpoints.py [path-to-kima-hub] > docs/api-endpoints.md
"""
import re, sys, pathlib, collections

ROOT = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "../kima-hub")
BACKEND = ROOT / "backend" / "src"

IMPORT_RE = re.compile(r'import\s+(?:\*\s+as\s+)?([A-Za-z0-9_]+)\s+from\s+["\']([^"\']+)["\']')
# Re-export barrels: routes/library.ts is two lines that forward to library/index.ts.
REEXPORT_RE = re.compile(r'export\s*\{\s*default\s*\}\s*from\s*["\']([^"\']+)["\']')
# router.use("/prefix"?, ...middleware?, routerVar) — the router is the argument
# ending in Routes/Router (apiLimiter-first is the house style).
USE_RE = re.compile(r'\b(?:router|app)\.use\(([^)]*)\)')
VERB_RE = re.compile(r'router\.(get|post|put|patch|delete)\(\s*"([^"]*)"')
ROUTER_ARG_RE = re.compile(r'\b([A-Za-z0-9_]+(?:Routes|Router))\b')


def resolve_module(spec, from_file, depth=0):
    """Resolve a TS module specifier ('./artists', '../x') to the source file that
    declares the routes — following `export { default } from` barrels, which are how
    this backend points a mount at a directory's index file."""
    if spec.startswith("."):
        base = (from_file.parent / spec).resolve()
    else:
        base = (BACKEND / spec).resolve() if not spec.startswith("/") else pathlib.Path(spec)
    target = None
    for cand in (base.with_suffix(".ts"), base / "index.ts"):
        if cand.is_file():
            target = cand
            break
    if target is None or depth >= 8:
        return target
    spec = REEXPORT_RE.search(target.read_text())
    if not spec:
        return target
    return resolve_module(spec.group(1), target, depth + 1)


def router_vars_in(args):
    """Router identifiers in a .use(...) argument list, with any leading path prefix."""
    args = args.strip()
    prefix = ""
    m = re.match(r'^"([^"]*)"\s*,\s*(.*)$', args, re.S)
    rest = args
    if m:
        prefix, rest = m.group(1), m.group(2)
    return prefix, [v for v in ROUTER_ARG_RE.findall(rest) if "Limiter" not in v]


def index_of(file):
    """Variable -> module specifier, for one file's imports."""
    return {name: spec for name, spec in IMPORT_RE.findall(file.read_text())}


index_ts = BACKEND / "index.ts"
if not index_ts.is_file():
    sys.exit(f"no backend at {index_ts} — pass the path to a kima-hub checkout")

# 1. top-level mounts declared in index.ts.
mounts = []                                   # (path, file) — ordered, for the header
mount_by_var = {}                             # var -> file
imports_index = index_of(index_ts)
for m in re.finditer(r'\bapp\.use\(\s*"(/api/[^"]*)"([^)]*)\)', index_ts.read_text()):
    _prefix, vars_ = router_vars_in(m.group(2))
    for var in vars_:
        spec = imports_index.get(var)
        target = resolve_module(spec, index_ts) if spec else None
        if target is None:
            continue
        mounts.append((m.group(1), target))
        mount_by_var.setdefault(var, target)

# 2. walk the mount graph, accumulating URL prefixes. A file mounted twice
# (or mounted under two prefixes) contributes its routes under each.
text_cache = {}
def text_of(f):
    if f not in text_cache:
        text_cache[f] = f.read_text()
    return text_cache[f]

def mounted_children(f):
    """(sub-prefix, target file) for every router this file mounts."""
    imports = index_of(f)
    out = []
    for m in USE_RE.finditer(text_of(f)):
        prefix, vars_ = router_vars_in(m.group(1))
        for var in vars_:
            spec = imports.get(var)
            target = resolve_module(spec, f) if spec else None
            if target is not None:
                out.append((prefix, target))
    return out

domain_rows = collections.defaultdict(list)
seen = set()
queue = [(path, target, 0) for path, target in mounts]
while queue:
    prefix, f, depth = queue.pop()
    if depth > 8:                             # a cycle in the mount graph
        continue
    key = (prefix, f)
    if key in seen:
        continue
    seen.add(key)
    rel = str(f.relative_to(BACKEND))
    for verb, p in VERB_RE.findall(text_of(f)):
        p = re.sub(r":[A-Za-z0-9_]+", ":param", p)
        # A router mounted at /api/playlists answers router.get("/") at /api/playlists,
        # so the document lists the URL a client types, not the mount joined to a slash.
        full = (prefix + p).rstrip("/")
        domain_rows[prefix].append((verb, full, rel))
    for sub, target in mounted_children(f):
        queue.append((prefix + sub.rstrip("/"), target, depth + 1))

# 3. route files no mount reaches, so the gap is visible rather than silent.
reached = {f for _, f in seen}
for f in sorted((BACKEND / "routes").rglob("*.ts")):
    if "__tests__" in f.parts or f.name.endswith(".d.ts") or f in reached:
        continue
    stem = f.stem
    for verb, p in VERB_RE.findall(f.read_text()):
        p = re.sub(r":[A-Za-z0-9_]+", ":param", p)
        domain_rows[f"(unmounted) {stem}"].append((verb, f"(mount?) /{stem}{p}".rstrip("/"),
                                                  str(f.relative_to(BACKEND))))

out = []
out.append("# Kima API — endpoint surface (auto-extracted)\n")
out.append("_Generated by `scripts/extract-api-endpoints.py` from "
           "`backend/src/routes/**/*.ts` + `backend/src/index.ts` mounts. "
           "The native client must reach the user's own Kima server at "
           "`<server>/api/...`. Auth = JWT Bearer (see /api/auth)._\n")
total = sum(len(v) for v in domain_rows.values())
out.append(f"_Surface: {total} endpoints across {len(domain_rows)} domains._\n")
out.append("## Top-level mounts (`backend/src/index.ts`)\n```\n" +
           "\n".join(sorted({f'"{p}" -> {t.relative_to(BACKEND)}' for p, t in mounts})) + "\n```\n")
out.append("## Endpoints by domain\n")
for domain in sorted(domain_rows):
    rows = domain_rows[domain]
    src = sorted({r[2] for r in rows})
    out.append(f"### {domain}  \n_source: {', '.join(src)}_\n")
    for verb, full, _ in sorted(set(rows)):
        out.append(f"- `{verb.upper():6s} {full}`")
    out.append("")
print("\n".join(out))
