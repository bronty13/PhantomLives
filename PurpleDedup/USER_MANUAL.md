# PurpleDedup — User Manual

Phase 1 walkthrough. The GUI and CLI share the same engine; pick whichever fits the
task.

## What it does today

Three kinds of duplicate detection, each emitting its own cluster type:

1. **Exact (`kind: "exact"`)** — files whose bytes are bit-for-bit identical, found by
   size bucketing then SHA256 hashing. Every exact cluster is a guaranteed duplicate.
2. **Similar photos (`kind: "similar_photo"`)** — photos that *look* the same but were
   resized, recompressed, or re-encoded between copies. Found by perceptual hashing
   (pHash + dHash) on photo extensions (JPEG, HEIC, PNG, RAW, …). Similar clusters are
   *high-confidence-but-not-guaranteed* duplicates; review before deleting.
3. **Similar videos (`kind: "similar_video"`)** — videos that look the same but were
   re-encoded at a different resolution / bitrate / codec. Found by sampling 1 frame
   per second via AVFoundation, perceptually hashing each frame, and aligning the
   resulting sequences. Coverage = whatever AVFoundation natively decodes (MP4, MOV,
   M4V, MPG, ProRes, HEVC, H.264). MKV / AVI / WMV / WebM are **not supported** in
   today's release; those files are skipped with a logged warning and the rest of the
   scan continues.

Files already in an exact cluster are excluded from the similar passes to keep the
output clean.

## GUI

1. Open `PurpleDedup.app`.
2. Drag one or more folders into the **Sources** area, or click **Add Folder…**.
3. Click **Scan**. Progress streams under the button.
4. Each result row is a cluster: a SHA256 hash, a per-file size, and the list of
   paths that share it. The header shows how many bytes you'd reclaim if you kept
   one copy from each cluster and discarded the rest.

Phase 1 stops at "show me what's duplicated." Trashing files happens through the CLI
or by hand for now; the GUI **Move to Trash** button arrives in Phase 5 along with
the auto-select rules.

## Audit a folder against your Photos library

The window has a mode switch at the top: **Find Duplicates** (above) and
**Audit vs Photos**. The audit answers a different question — *which files in
this folder are already in my Photos library, and which are missing?* — and
lets you import the missing ones.

1. Switch to **Audit vs Photos**.
2. Pick a **Folder to audit** and your **Photos library** (`.photoslibrary`).
3. Choose a **Match mode**:
   - **Perceptual** (default): a folder file counts as "in Photos" if it's
     byte-identical to a library original **or** visually matches one (so
     re-encoded / resized copies are recognised).
   - **Exact**: byte-identical originals only.
   - **Include hidden Photos items** (default on): also compares against your
     Hidden album, and gives any match that lives *only* in Hidden a pink
     **Hidden** tag so you can find it. Turn it off to treat hidden-only
     matches as missing.
   - **Match on-device previews** (default on): under iCloud "Optimize Mac
     Storage", most full originals aren't on this Mac, but Photos keeps a small
     preview of each. This matches your folder photos against those previews by
     *content*, so a photo is found even when its original is in iCloud —
     tagged **In Photos (preview)**. The first audit of a large library takes a
     bit longer while previews are hashed; later audits are fast (cached).
4. Click **Audit**. The results list shows every file with a status badge:
   **In Photos** (exact), **Likely · d=N** (perceptual match, with distance),
   **In Photos (preview)** (matched your library's on-device preview — the
   original is in iCloud), **Same name** (filename matches a library original —
   likely an iCloud-optimised copy), or **Not in Photos**. Hidden items get an extra tag:
   a pink **Hidden** when the match lives *only* in your Hidden album, or an
   indigo **Also Hidden** when the same item is in Photos both normally and
   hidden.
5. Use the **All / In Photos / Missing** filter at the top to focus. Click
   **Select all missing**, review, then **Import N → Photos**. A preflight
   confirms the count; importing **copies** the originals into Photos (your
   files on disk are never moved or deleted) and collects them in an
   "Imported by PurpleDedup" album. The list re-audits itself afterward.

**Accuracy notes.** Exact mode misses recompressed copies — use perceptual
(the default). **iCloud "Optimize Mac Storage":** when this is on, most
full-resolution originals live in iCloud and are *not* in the on-disk
`originals/` folder the byte/visual matcher reads — so those items can only be
matched by **filename** (the "Same name" tag), which works because a Photos
drag-export keeps the original name even across a format change
(`IMG_1234.HEIC` → `IMG_1234.jpeg`). The audit shows a note when it detects
this. For full exact/visual matching, pick "Download Originals to this Mac" in
Photos › Settings › iCloud. Live Photos import as separate still + video assets
in this version.

## CLI

```
pdedup scan <path>...        # default: photos + videos, hidden files skipped
```

### Common invocations

```bash
# Scan one folder, pretty JSON to stdout.
pdedup scan ~/Pictures

# Two folders, write the report to a file.
pdedup scan ~/Pictures /Volumes/Backup/Photos -o ~/Downloads/PurpleDedup/report.json

# Photos only; quiet output suitable for cron / shell scripts.
pdedup scan ~/Pictures --photos-only --quiet

# Treat *every* file as a candidate (handy for testing on a fixture directory).
pdedup scan ./fixtures --all-files

# Audit a folder against your Photos library (read-only; JSON report of in/missing).
pdedup audit ~/SomeFolder --against ~/Pictures.photoslibrary

# ...and import the files that are missing from Photos (copies, never moves).
pdedup audit ~/SomeFolder --against ~/Pictures.photoslibrary \
    --import-missing --import-album "Imported by PurpleDedup"
```

The `audit` subcommand takes `--match exact|perceptual` (default perceptual),
`--perceptual-threshold N`, the same kind filters as `scan`, `--no-cache`, and
`-o <path>`. Hidden Photos items are compared by default and flagged
(`inPhotosHidden` / `hiddenInPhotosCount` in the JSON); pass
`--exclude-hidden-photos` to drop them from the comparison. It only writes to
Photos when `--import-missing` is given.

### Flags

| Flag | What it does |
|---|---|
| `-o, --output <path>` | Write the JSON report here instead of stdout. Parent dir auto-created. |
| `--photos-only` | Restrict to photo extensions (jpg, heic, png, raw…). |
| `--videos-only` | Restrict to video extensions (mp4, mov, m4v…). |
| `--all-files` | Skip extension filtering — scan every regular file. |
| `--hidden` | Include dotfiles and other hidden entries. |
| `--similar-threshold N` | Photo perceptual threshold (Hamming distance). Default 6. 6 = "very similar," 12 = "loosely similar." |
| `--no-similar` | Skip the perceptual photo pass. |
| `--video-threshold N` | Video perceptual threshold (mean Hamming over aligned frames). Default 6. Same scale as photos. |
| `--no-similar-videos` | Skip the perceptual video pass. |
| `-q, --quiet` | Errors only. |
| `-v, --verbose` | Extra progress lines on stderr. |
| `--compact` | Emit JSON without pretty-printing. |

### Picking a similarity threshold

The perceptual pHash is a 64-bit fingerprint; the threshold is the maximum number of
bits that may differ for two photos to land in the same cluster. Empirically:

| Threshold | What it catches | Trade-off |
|---|---|---|
| 0 | Identical pHashes (rare; most encoding produces some bit drift) | Misses everything but the most boring cases. |
| **6** (default) | Resampled / recompressed copies of the same source | Rarely false-positives. Misses some heavily-edited variants. |
| 10–12 | "Loosely similar": minor crops, white-balance shifts, light filters | Some false positives; review before bulk delete. |
| 16+ | Different shots from the same scene, distant variations | Lots of false positives; useful for *manual* discovery, not auto-cleanup. |

The threshold is set per-scan today. Adjusting it without rescanning the library
(FR-2.5's slider) lands in Phase 4 once the cache populates fingerprints to disk.

### JSON output shape

```jsonc
{
  "appName": "PurpleDedup",
  "appVersion": "0.2.0",
  "generatedAtISO": "2026-05-09T13:42:18Z",
  "sources": ["/Users/you/Pictures"],
  "totalFilesScanned": 12450,
  "totalCandidatesHashed": 312,
  "exactClusterCount": 47,
  "similarClusterCount": 18,
  "totalClusters": 65,
  "totalReclaimableBytes": 3221225472,
  "similarityThreshold": 6,
  "clusters": [
    {
      "kind": "exact",
      "contentHash": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
      "sizeBytes": 4212345,
      "fileCount": 3,
      "reclaimableBytes": 8424690,
      "files": [
        { "path": "/…/IMG_4521.jpg", "sizeBytes": 4212345,
          "modificationTimeISO": "2024-03-15T18:42:11Z", "isLocked": false }
      ]
    },
    {
      "kind": "similar_photo",
      "fileCount": 4,
      "reclaimableBytes": 12000000,
      "maxPairwiseDistance": 4,
      "files": [
        { "path": "/…/IMG_4521-edited.jpg", "sizeBytes": 3800000,
          "modificationTimeISO": "2024-03-15T18:43:02Z", "isLocked": false,
          "phash": "9a3c…", "dhash": "f071…", "width": 4032, "height": 3024 }
      ]
    }
  ]
}
```

`maxPairwiseDistance` is the diameter of the cluster — the largest pHash Hamming
distance between any two members. Lower numbers mean tighter visual similarity. The
top-level `similarityThreshold` echoes back the threshold used for the scan.

`totalCandidatesHashed` divided by `totalFilesScanned` is roughly your size-bucket
hit rate — small numbers mean Stage 1 saved you most of the I/O.

## Where things live

| Purpose | Path |
|---|---|
| Reports written by `-o` (default suggestion) | `~/Downloads/PurpleDedup/` |
| Auto-backup archives | `~/Downloads/PurpleDedup backup/` |
| SQLite cache + settings | `~/Library/Application Support/PurpleDedup/` |

## Cache and second runs

PurpleDedup caches every file's content hash and perceptual fingerprint in a
local SQLite database. The first scan of a folder is full price (size bucket →
SHA256 → pHash + dHash → video fingerprint where applicable). The **second**
scan of the same folder reads everything from the cache as long as `(path,
size, mtime)` haven't changed — typically a >10× speedup on real libraries.

The cache also makes the threshold steppers cheap: change the photo or video
threshold and click Scan again, and the engine re-clusters from cached
fingerprints without re-hashing anything. Adjust until the results look right.

The cache lives at `~/Library/Application Support/PurpleDedup/purplededup.sqlite`
and is auto-managed. To start fresh, delete the file; the next scan rebuilds.

## Backups

PurpleDedup runs an automatic backup on every launch (PhantomLives convention).
Default retention: 14 days. Default location: `~/Downloads/PurpleDedup backup/`.
A 5-minute debounce prevents rapid relaunches from filling the folder.

The backup archives the entire `~/Library/Application Support/PurpleDedup/`
directory — that's the SQLite cache plus your settings. To change retention,
disable auto-backup, or pick a different folder, open **Settings → Backup**
(`Cmd+,` in the app). The retention trim only deletes files matching the
`PurpleDedup-` prefix, so anything else you store in the backup folder is left
alone.


## What today's release *can't* do (yet)

- MKV / AVI / WMV / WebM video formats — AVFoundation alone can't decode them.
  Files in these formats are skipped per-file. (FFmpeg fallback is deferred; binary
  size + license complexity outweigh the niche format coverage for now.)
- Side-by-side comparison view, EXIF panel, QuickLook → **Phase 4**
- Adjusting similarity threshold without rescan → **Phase 4** (needs the cache)
- Smart-select rules and bulk cleanup workflow → **Phase 5**
- Apple Photos library scanning → **Phase 6**

Each phase will land behind no flags — when it ships, it ships.

## Troubleshooting

- **"Permission denied" on `~/Pictures`**: macOS Photo permissions only matter for
  the Apple Photos library bundle (Phase 6). For an ordinary folder, grant your
  terminal full disk access via System Settings → Privacy & Security → Full Disk
  Access.
- **Gatekeeper warning on first launch**: PurpleDedup is signed ad-hoc by default
  for personal use. Right-click the app → Open the first time, then macOS
  remembers it.
- **Scan seems to hang**: the walking phase is silent until ~256 files; stderr will
  start streaming after that. For very small folders the whole scan can finish
  before any progress prints.
