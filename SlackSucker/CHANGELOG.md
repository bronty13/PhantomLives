# SlackSucker changelog

## 1.1.x — post-processing pipeline (2026-05-15)

A batch of post-archive enhancements. The slackdump invocation itself
is unchanged; everything new runs after slackdump exits 0.

### UI

- **Reveal / Open DB chip order swapped** in the live-output card so
  the more-common "Open DB" sits to the left of "Reveal in Finder".
- **Backup Settings**: added top-level **Reveal folder**, **Verify latest**,
  and **Restore latest…** buttons alongside the existing per-row chips.
- **Main-screen export-folder card** above the live output. Shows the
  resolved output root, lets the user pick a per-session override
  (does NOT persist — Settings remains the source of the default;
  use Settings → Output to change the persistent default). Reset
  button returns to the Settings default; folder chip reveals it.

### New post-processing toggles

All four are independent, run in this order after slackdump exits, and
log to their own `<name>-log.txt` next to the SQLite. Failures in one
don't block the others. Defaults live in **Settings → POST-PROCESSING
DEFAULTS**; the main-screen toggles are per-run overrides.

- **Bake orientation** — reads EXIF `Orientation` from each photo and
  re-encodes via Core Image + ImageIO so the pixel data matches what
  every viewer renders, then resets `Orientation=1`. Videos: ffmpeg
  re-encode with `-display_rotation 0` + `rotate=0` metadata. Requires
  ffmpeg on PATH for videos; photos work without external deps. Runs
  BEFORE "Strip metadata" so the orientation hint isn't lost.
  *Out of scope*: ML-based people-upright inference for files without
  any orientation flag (screenshots, edited copies). That's a separate
  feature category.
- **Strip metadata** — `exiftool -all=` over Photos/ and Videos/.
  In-place destructive; the slackdump SQLite retains all message-level
  provenance. Requires `brew install exiftool`.
- **Transcribe A/V** — shells to the sibling `transcribe/transcribe.py`
  for every file under Videos/ and Audio/; emits `<name>.txt` next to
  the source. Apple Silicon only. Configurable Whisper model in
  Settings (tiny/base/small/medium/large/turbo; turbo is default).
  Discovery: `$SLACKSUCKER_TRANSCRIBE_BIN` → `which transcribe` →
  `~/Documents/GitHub/PhantomLives/transcribe/transcribe.py`.
- **Hashes** — writes `hashes.txt` at the run-folder root in GNU
  `sha256sum`-compatible format, grouped by algorithm. Configurable
  set of algorithms in Settings (MD5 / SHA-1 / SHA-256, multi-select;
  default SHA-256). Single-pass stream-hashes all selected algorithms
  per file via `CryptoKit`.

### New files

- `Services/HashService.swift` — `CryptoKit`-backed single-pass hasher.
  `Insecure.MD5`, `Insecure.SHA1`, and `SHA256` all updated from the
  same `Data.withUnsafeBytes` chunk so a 1GB file is read exactly once.
- `Services/OrientationBaker.swift` — `CGImageSource` + `CIImage.oriented`
  for photos; `ffmpeg -display_rotation 0 -c copy` for videos.
- `Services/MetadataStripper.swift` — batches paths through
  `exiftool -@ <argfile>` to avoid per-file process spawning and argv
  length limits on big runs.
- `Services/TranscriptionService.swift` — per-file async subprocess
  loop with stderr capture; bridges sync `Process` exit through
  `withCheckedContinuation` so UI stays responsive between files.
- `Tests/SlackSuckerTests/PostProcessingTests.swift` — 11 new tests
  across the four services + an `ArchiveOptions` legacy-JSON decode
  test (ensures 1.0.x settings.json files load cleanly post-upgrade).

### Settings & schema

- `ArchiveOptions` gained six new fields: `generateHashes`,
  `hashAlgorithms`, `transcribeMedia`, `transcribeModel`,
  `stripPhotoMetadata`, `bakeOrientation`. All decoded with
  `decodeIfPresent` + safe defaults so older settings.json files load
  without intervention.
- New `HashAlgorithm` and `TranscriptionModel` Codable enums.
- `ArchiveRequest` gained matching per-run fields.

### Tests

- **Total: 52 tests across 16 Swift Testing suites** (was 41 in 11).
  All pre-existing suites unchanged; 11 new tests across
  `HashService` × 4, `MetadataStripper` × 2, `OrientationBaker` × 3,
  `TranscriptionService` × 1, `ArchiveOptions backwards compat` × 1.

### Optional Homebrew dependencies

None of these are required at install time — the toggles surface
clear "tool not installed" messages in the live log when their
helpers are missing. To enable the features:

- `brew install exiftool` — for metadata stripping
- `brew install ffmpeg` — for video orientation baking
- `transcribe/` checked out alongside SlackSucker — for A/V transcription

## 1.0.x — initial release (2026-05-15)

Initial public release. Version numbers derive from git commit count via `build-app.sh`.

### Core

- SwiftUI macOS app driving a bundled `slackdump` binary at `SlackSucker.app/Contents/Resources/slackdump`. Re-signed with the host app's identity so TCC + notarisation see a single bundle.
- Plain SwiftPM, no XcodeGen. macOS 14+, Swift 5.9+.
- Developer-ID-signed by default; ad-hoc fallback when the cert isn't in the keychain.

### Scope + archive

- Targeted scope picker: **Entire workspace**, **Channel / DM** (with cached type-ahead picker), or **Thread URL** (Slack permalink).
- UTC time range with local-time pickers; "Archive all time" toggle.
- Per-run options: download files, download avatars, member-only channels (workspace-wide only).
- Output to `~/Downloads/SlackSucker/<scope>_<YYYYMMDD_HHmmss>/` by default; overridable in Settings.
- Run history (50 entries, sidebar shows 5); preset save/apply.

### Workspace auth (via slackdump)

- "Add workspace…" sheet shells to `slackdump workspace new <name>` with stdin piped so interactive prompts can be answered.
- "Overwrite? (y/N)" prompt detected and routed through a real Yes/No alert instead of busy-looping on closed stdin.
- Workspace list parser handles slackdump 4's `=> default (file: …)` format. `-workspace` flag positioned after the subcommand (slackdump rejects it before).

### Channel + user picker

- `slackdump list channels -format JSON` / `list users -format JSON`. Codable decoder against typed structs.
- DMs cross-referenced against users table → `@displayname` instead of `@<external>:USERID`.
- Archived channels and deleted users filtered out.
- Per-workspace cache at `~/Library/Application Support/SlackSucker/channel-cache/<workspace>.json`.
- Auto-refresh on workspace change, launch (when cache empty), and first switch to Channel/DM mode.

### Post-processing

- **`FileOrganizer`** (new) — moves `__uploads/<FILE_ID>/<name>` into `Videos/` `Photos/` `Audio/` `Other/` at the run-folder root. Collisions get a `(<FILE_ID>)` suffix instead of overwriting. Idempotent; safe to rerun. Toggle in Settings, default on. Writes `organize-log.txt` summary.
- **`ChatExporter`** (new) — renders a plain-text transcript into `Chat/<scope>.txt` for targeted scopes (channel / DM / thread). Thread replies indented under their parent. Resolves `<@U…>` / `<#C…|name>` / `<https://…|label>` Slack markup. Decodes HTML entities. File attachments listed under their parent message.
- **`archive.log`** captures every line slackdump streamed, written at run-folder root.

### Thread-URL workaround

- Slackdump 4.x doesn't fetch attachments when the scope argument is a permalink — `MESSAGE.NUM_FILES` gets set but the `FILE` table stays empty and `__uploads/` is never created.
- Fix in `ArchiveRequest.argumentList()`: thread URLs are rewritten to `<channel ID> -time-from <TS-1s> -time-to <TS+1s>` (UTC), which triggers slackdump's normal channel-archive file-download path.
- `ArchiveScope.parseThreadURL` extracts channel + TS from the permalink (regex against `/archives/(C[A-Z0-9]+)/p(\d+)`, split last 6 digits as microseconds).
- User-visible: `[scope] Thread URL — substituting channel archive with ±1s time bracket…` log line precedes the actual argv.

### Auto-backup on launch

- Per PhantomLives `CLAUDE.md` standard. `~/Downloads/SlackSucker backup/SlackSucker-<ts>.zip`, 14-day retention, 5-minute debounce, prefix-scoped trim.
- Settings → Backup pane: toggle, path picker, retention stepper, "Run backup now", recent-backups list with Test (non-destructive verify) / Restore (with pre-restore safety backup) / Reveal.

### `install.sh`

- New PhantomLives convention: `install.sh` script alongside `build-app.sh` for `.app` subprojects.
- Quits the running app, removes `/Applications/SlackSucker.app`, ditto-copies the freshly built bundle, relaunches.
- `--no-open` flag suppresses the relaunch step.
- Reference implementation for the new PhantomLives "install.sh standard" added to root `CLAUDE.md`.

### Tests

- 41 tests across 11 Swift Testing suites:
  - `ArchiveRequest` × 8 — argv per scope × time × flags; thread-URL rewrite; malformed URL fallback; slug sanitisation
  - `LineBuffer` × 2 — CR/LF/bareCR; trailing drain
  - `RunStats` × 2 — counts; phase detection
  - `ArchiveRunner helpers` × 1 — PATH augmentation idempotency
  - `WorkspaceService parser` × 3 — v4 list format; chrome filtering; overwrite-prompt detection
  - `ChannelService JSON parser` × 5 — channels JSON; merge with users; archive/deleted filters; lenient JSON extraction; empty
  - `FileOrganizer` × 5 — category classification; reorg; collision suffix; no-op; idempotency
  - `ChatExporter` × 6 — thread indentation; user mentions; channel + URL + entity decoding; file listing; unknown user fallback; timestamp
  - `SlackdumpBinary` × 2 — chmod bit; resolution
  - `Settings & history round-trips` × 2 — JSON encode/decode; max-entries
  - `BackupService` × 4 — debounce; retention trim; target auto-create; list newest-first

### Hygiene

- Process working directory pinned to `/tmp` when capturing slackdump output, so any side-effect files slackdump leaks don't pollute the project tree.
- Added `-no-json` / `-format JSON` flags to `slackdump list` invocations to stop slackdump from auto-saving cache files to cwd.
