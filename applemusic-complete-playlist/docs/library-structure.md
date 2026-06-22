# Apple Music library structure

How the playlists this toolkit builds are organized, the containment rules that
hold them together, and how to validate them. Snapshot: **2026-06-22**, ~263
project playlists, **66,302 / 100,000** unique library songs (66.3%).

All playlists use the `[PL]` suffix and **Flavor A** (every recording, not deduped
by name). Counts below are catalog ids tracked in each playlist's local manifest.

---

## Three top-level structures

The library has three independent organizing structures. They overlap in *songs*
(a Metallica track can be in `Metallica Complete`, `Thrash Metal`, `Metal —
Complete`, and `80s — 1986`) but each is its own browsable hierarchy.

```
1. DECADE COLLECTION      time-and-genre, chart-built   (70s–2010s)
2. GENRE / ARTIST         metal breadth + discographies, classical renditions
3. STANDALONE             Life in Music, Brent Mason — Played On
```

---

## 1. The Decade Collection (chart-built)

Five decades — `70s`, `80s`, `90s`, `2000s`, `2010s` — each with the **same shape**.
Built by `build_decade_charts.py` from Billboard charts (pop/country/AC) + Apple
editorial (metal/rock).

```
{D} — Complete [PL]                 ← DECADE MASTER (pop ∪ AC ∪ Rock ∪ Metal)
│
├── {D} — 1990 [PL] … {D} — 1999 [PL]      pop per-year, Billboard Year-End Hot 100
├── {D} Adult Contemporary — Complete [PL]  ← folds INTO the master
│   └── {D} Adult Contemporary — 1990 [PL] … 1999 [PL]    AC weekly #1s
├── {D} — Rock [PL]                          ← folds INTO the master (editorial AOR)
└── {D} — Metal [PL]                         ← folds INTO the master (editorial)

{D} Country — Complete [PL]          ← SEPARATE country master (NOT folded in)
└── {D} Country — 1990 [PL] … 1999 [PL]      Billboard Year-End Country ∪ weekly #1s
    (+ {D} Country — Essentials [PL] on some decades — legacy editorial)
```

### Per-category totals (5 decades)

| Tier | Playlists | Songs | Source |
|---|---:|---:|---|
| Decade master (`{D} — Complete`) | 5 | 11,432 | union of the rows below |
| Decade pop per-year (`{D} — YYYY`) | 50 | 10,675 | Billboard Year-End Hot 100 |
| Country master (`{D} Country — Complete`) | 5 | 3,906 | year-end ∪ #1s |
| Country per-year (`{D} Country — YYYY`) | 50 | 4,017 | year-end ∪ #1s |
| Country essentials (legacy) | 4 | 400 | Apple editorial |
| AC master (`{D} Adult Contemporary — Complete`) | 5 | 670 | AC weekly #1s |
| AC per-year (`{D} Adult Contemporary — YYYY`) | 50 | 714 | AC weekly #1s |
| Decade Metal stream (`{D} — Metal`) | 5 | 1,614 | Apple editorial |
| Decade Rock stream (`{D} — Rock`) | 5 | 500 | Apple editorial |

### Containment rules (the invariants)

For every decade `D`:

1. **`{D} — Complete` ⊇ each `{D} — YYYY`** — no pop-year song missing from the master.
2. **`{D} — Complete` ⊇ `{D} Adult Contemporary — Complete`** — AC folds in.
3. **`{D} — Complete` ⊇ `{D} — Rock`** and **⊇ `{D} — Metal`** — rock & metal fold in.
4. **`{D} Country — Complete` ⊇ each `{D} Country — YYYY`**.
5. **`{D} Adult Contemporary — Complete` ⊇ each AC per-year**.

**Country is deliberately NOT folded into the decade master** (your preference: a
separate country set). The only country songs that appear in `{D} — Complete` are
genuine **pop crossovers** — 1% (80s/90s) rising to 11% (2010s) as country crossed
to the Hot 100 more in the streaming era. That overlap is correct, not a leak.

→ Validate with `validate_structure.py` (reads manifests, checks all five rules).
Last run: **all invariants hold across all five decades ✓**.

### Why these design choices

- **Pop, AC, Rock, Metal fold into one decade master** so `{D} — Complete` is a
  single "everything from the decade" list — the "remember the past" playlist.
- **Country stays separate** because it's a distinct listening mode; folding it would
  swamp the decade master with ~800–950 country songs that aren't what you reach for
  under "80s."
- **AC carries a year** (weekly #1 issue date) so it distributes to per-year lists;
  **metal/rock are decade-level editorial** with no per-year data, so they only fold
  into the master.

---

## 2. The Genre / Artist Collection

### Metal (bridges the "no metal chart ever existed" gap)

Metal was never charted as singles, so it's built two ways — **breadth** (editorial
sub-genres) and **depth** (full discographies):

```
Metal — Complete [PL]            2,071  ← all sub-genre streams, deduped
├── Thrash Metal [PL]              446
├── Classic & Heavy Metal [PL]     762
├── Death Metal [PL]               189
├── Symphonic, Folk & Viking …     120
├── Doom & Sludge / Glam & Hair / Metalcore / Black / Progressive /
│   Instrumental / Groove / Power Metal [PL]   (12 sub-genre streams total)
│
└── canon discographies (every recording, Flavor A):
    Motörhead 1771 · Metallica 1456 · Megadeth 649 · Sepultura 623 ·
    Black Sabbath 573 · Judas Priest 567 · Ozzy 565 · Anthrax 543 ·
    Death 530 · Iron Maiden 491 · Slipknot 458 · Slayer 393 · Dio 359 ·
    Opeth 308 · Mastodon 288 · Lamb of God 276 · Testament 238 ·
    Amon Amarth 238 · Pantera 220 · Gojira 138 · System of a Down 136
```

The sub-genre streams + `Metal — Complete` are the **breadth**; the `<Band> Complete`
discographies are the **depth**. They're kept separate on purpose — folding 21
every-recording discographies (~10,300 songs) into `Metal — Complete` would bury the
curated 2,071 breadth under one-band bulk.

### Artist completes (all genres)

`<Artist> Complete [PL]` — every available recording + features for one artist, built
by `build_playlist.py`. **67 playlists, 43,599 songs** (the 21 metal ones above plus
Taylor Swift, The Beatles, Ella Fitzgerald 4,604, Pearl Jam 6,982, U2, etc.).

### Classical renditions

`<Artist> — Classical Renditions [PL]` — string-quartet/piano tribute albums of an
artist's songs, built by `classical_covers.py`. Taylor Swift (405) and Sabrina
Carpenter (72).

---

## 3. Standalone

| Playlist | Songs | What |
|---|---:|---|
| `Life in Music [PL]` | 416 | The legacy music diary — synced from a Spotify playlist (the point of MusicJournal). |
| `Brent Mason — Played On [PL]` | 603 | Session-guitarist discography assembled from a curated Spotify playlist (Exportify → match). |

---

## Library accounting

- **~263 project playlists**, **83,348 tracked song-slots** (manifests sum, with
  cross-playlist overlap), resolving to **66,302 unique library songs**.
- The binding limit is Apple's **100,000-song library cap** — every playlist song
  counts toward it. At 66.3% we have ~33.7k headroom. The discography builds are the
  heavy consumers (artist completes alone are ~44k of the tracked slots).
- `check_limits.py` reports headroom; `build_playlist` warns at 85% / 95%.

## Which tool builds what

| Tool | Builds |
|---|---|
| `build_decade_charts.py` | The entire Decade Collection (pop/country/AC + metal/rock folds). |
| `build_playlist.py` | `<Artist> Complete` discographies (incl. the metal canon). |
| `build_metal` streams (ad-hoc, from editorial) | `Metal — Complete` + sub-genre streams. |
| `classical_covers.py` | `<Artist> — Classical Renditions`. |
| `sync_playlist.py` | `Life in Music`, `Brent Mason — Played On` (chart/CSV → match). |
| `validate_structure.py` | Checks the decade containment invariants. |
