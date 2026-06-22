#!/usr/bin/env python3
"""Map the library's decade→master structure and validate containment invariants.

Uses the local manifests (the authoritative record of catalog ids added to each
playlist) so checks don't depend on Apple's lossy library read-back.
Invariants checked per decade:
  - master ⊇ each per-year      (no year song missing from the decade master)
  - master ⊇ AC master         (AC folds into the decade master)
  - master ⊇ Rock stream       (Rock folds in)
  - master ⊇ Metal stream      (Metal folds in)
  - Country master ⊇ Country years
  - AC master ⊇ AC years
"""
import json, re, sys
sys.path.insert(0, ".")
import build_playlist as bp

cfg = bp.load_config()
am = bp.AppleMusic(bp.sign_developer_token(cfg), bp.load_user_token(), throttle=0.04)

# name -> library playlist id
name2id = {}
for pl in am.get_paginated("/v1/me/library/playlists", limit=100):
    name2id[pl.get("attributes", {}).get("name", "")] = pl["id"]

def ids(name):
    pid = name2id.get(name)
    return bp.load_manifest(pid) if pid else None

DECADES = ["70s", "80s", "90s", "2000s", "2010s"]

def check(label, sub, sup):
    """sub ⊆ sup ?  returns (ok, n_missing, sub_size)"""
    if sub is None or sup is None:
        return None
    missing = sub - sup
    return (len(missing) == 0, len(missing), len(sub))

print("=" * 72)
print("DECADE STRUCTURE VALIDATION (via manifests)")
print("=" * 72)
overall_ok = True
for d in DECADES:
    M = ids(f"{d} — Complete [PL]")
    print(f"\n### {d}   master '{d} — Complete [PL]': {len(M) if M is not None else 'MISSING'} ids")
    if M is None:
        overall_ok = False; continue
    # per-year pop ⊆ master
    years = [y for y in range(int(d[:4]) if d[0]=='2' else 1900+int(d[:2]),
                               (int(d[:4]) if d[0]=='2' else 1900+int(d[:2]))+10)]
    yr_union = set()
    miss_years = []
    for y in years:
        yi = ids(f"{d} — {y} [PL]")
        if yi is None:
            miss_years.append(str(y)); continue
        yr_union |= yi
        r = check("", yi, M)
        if r and not r[0]:
            print(f"    ✗ {d} — {y} [PL]: {r[1]}/{r[2]} ids NOT in master")
            overall_ok = False
    if miss_years:
        print(f"    · per-year playlists absent: {', '.join(miss_years)}")
    ru = check("years∪", yr_union, M)
    print(f"    pop years ∪ = {len(yr_union)}  →  {'all in master ✓' if ru and ru[0] else f'{ru[1]} MISSING ✗'}")
    # folded supplements ⊆ master
    for label, nm in [("AC master", f"{d} Adult Contemporary — Complete [PL]"),
                      ("Rock", f"{d} — Rock [PL]"), ("Metal", f"{d} — Metal [PL]")]:
        si = ids(nm)
        r = check(label, si, M)
        if r is None:
            print(f"    · {label}: (absent)")
        else:
            print(f"    {label} ⊆ master: {'✓' if r[0] else f'✗ {r[1]}/{r[2]} missing'}  ({len(si)} ids)")
            if not r[0]: overall_ok = False
    # country master ⊇ country years
    CM = ids(f"{d} Country — Complete [PL]")
    if CM is not None:
        cu = set()
        for y in years:
            ci = ids(f"{d} Country — {y} [PL]")
            if ci: cu |= ci
        r = check("", cu, CM)
        verdict = "✓" if r and r[0] else ("✗ %d missing" % (r[1] if r else -1))
        print(f"    Country master {len(CM)} ⊇ country years ∪ {len(cu)}: {verdict}")
        if r and not r[0]: overall_ok = False
    # AC master ⊇ AC years
    ACM = ids(f"{d} Adult Contemporary — Complete [PL]")
    if ACM is not None:
        au = set()
        for y in years:
            ai = ids(f"{d} Adult Contemporary — {y} [PL]")
            if ai: au |= ai
        r = check("", au, ACM)
        verdict = "✓" if r and r[0] else ("✗ %d missing" % (r[1] if r else -1))
        print(f"    AC master {len(ACM)} ⊇ AC years ∪ {len(au)}: {verdict}")
        if r and not r[0]: overall_ok = False

print("\n" + "=" * 72)
print("RESULT:", "ALL INVARIANTS HOLD ✓" if overall_ok else "VIOLATIONS FOUND ✗ (see above)")
