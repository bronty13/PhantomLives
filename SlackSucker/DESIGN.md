# SlackSucker — Design notes

Why the code looks the way it does. Read after `HANDOFF.md` (which says *what* lives where) — this one's about *why*.

## Constraints that shaped the design

1. **Slackdump owns the protocol.** Slack's web API, auth, rate-limiting, retry, retry-after, and credential encryption are all slackdump's problem. SlackSucker is a GUI on top of a CLI — it should never replicate any of that.
2. **End user shouldn't need a separate slackdump install.** Bundle it inside the `.app`. Re-sign so TCC and notarisation are happy.
3. **One persistent token store, not two.** Slackdump already encrypts workspace creds in `~/Library/Caches/slackdump/`. Reimplementing that securely is a hard problem we don't have to solve.
4. **Targeted exports more than whole-workspace.** Most user intent is "archive this DM" / "back up this channel" / "save this thread before someone deletes it". Whole-workspace is a fallback case.
5. **Output should be human-grokkable, not just machine-grokkable.** Slackdump's native SQLite + `__uploads/<FILE_ID>/<name>` layout is round-tripable but ugly to navigate. People want photos in `Photos/` and a `.txt` they can read.

Those five constraints, in order, explain every non-obvious choice below.

## Decision log

### 1. Bundle `slackdump` instead of finding it on PATH

**Considered**: lookup `which slackdump` at app launch, fall back to a Settings field. Cleaner separation, no signing dance.

**Chosen**: copy slackdump into `Contents/Resources/` at build time and re-sign it with the host app's identity.

**Why**:
- Removes a class of "works on my machine" bugs caused by slackdump version drift between users.
- Single TCC entry — slackdump as a sibling binary doesn't accumulate its own permission grants.
- `Bundle.main.url(forResource:)` is a one-liner; no shell PATH parsing or `tccutil` rotation logic.
- Updating slackdump = rerun `build-app.sh`. Same cost either way; users don't need to know.

**Trade-off**: `.app` size jumps by ~36MB (the slackdump Go binary). Acceptable for a tool used to download multi-GB Slack archives.

### 2. Plain SwiftPM, no XcodeGen

**Considered**: XcodeGen + `project.yml`, matching Timeliner / MasterClipper.

**Chosen**: vanilla `Package.swift`, modelled on PurpleIRC and messages-exporter-gui.

**Why**:
- Single executable target with one source dir and one test dir. XcodeGen earns its keep on multi-platform / multi-target projects; here there's nothing to generate.
- One less moving part. `swift build` and `swift test` work directly.
- `build-app.sh` already does the manual `.app` assembly anyway — XcodeGen wouldn't simplify the build script.

### 3. JSON over text parsing for slackdump output

**First iteration**: parsed `slackdump list channels` text columns (the `ID  Arch  What` table). 

**Bugs that surfaced**:
- The help text said `-no-save`; the actual binary flag was `-no-json` (silent help drift).
- Private channels had a `🔒` glyph prefix that needed stripping.
- DMs showed as `@<external>:USERID` — required a separate users-list fetch to resolve to friendly names.
- Slackdump's logger emits ANSI-coloured `INFO` lines on stderr that bled into stdout in some configurations.

**Second iteration**: `slackdump list channels -format JSON` → `JSONDecoder` against Codable mirrors.

**Why**:
- Slack's API field naming is the structured contract; slackdump's text format is a presentation layer.
- Type-checked decode kills entire classes of bugs (wrong column count, missing field, encoding drift).
- DM resolution becomes a local merge against the users JSON (no extra API round-trip; no `-resolve` flag).
- Fixture-based tests now use real-shape JSON captured from the maintainer's workspace.

### 4. Channel-archive workaround for thread URLs

**Problem**: `slackdump archive https://x.slack.com/archives/C123/p1700…` exits in 400ms with `NUM_FILES=10` but FILE-table empty and `__uploads/` absent. Verified across `slackdump dump`, `slackdump tools redownload`, and three permutations of the archive command — slackdump 4.x simply doesn't fetch attachments when the scope arg is a thread permalink.

**Considered options**:

| Approach | Cost | Drawback |
| --- | --- | --- |
| Download files ourselves via HTTP | We'd need Slack auth | Reaches into slackdump's encrypted creds |
| Use `slackdump dump` instead | Different output (JSON files) | Breaks our SQLite-based ChatExporter |
| `slackdump tools redownload` | One extra call | Only validates known FILE rows; useless when FILE is empty |
| Channel-scoped archive with time bracket | Argv-layer fix only | Could pick up an unrelated adjacent message |

**Chosen**: rewrite the argv at request-build time. `.threadURL(url)` becomes the parent channel ID + `-time-from <TS-1s>` + `-time-to <TS+1s>`, formatted as UTC. ±1 second is tight enough to almost never collide with another message; slackdump's channel-archive flow then follows the thread tree if there are replies.

**Why**:
- Fix lives in pure code (`ArchiveRequest.argumentList()`), unit-tested with deterministic fixture URLs.
- No new permissions, no new auth surface, no new dependencies.
- User-facing log line (`[scope] Thread URL — substituting channel archive…`) makes the workaround transparent.
- If slackdump fixes the underlying bug upstream, removing the workaround is a one-`if`-block delete.

### 5. Post-archive reorganization, not slackdump-native format

**Considered**: leave slackdump's `__uploads/<FILE_ID>/<name>` structure alone. It's the round-trip-with-Slack-import format; tampering risks breaking `slackdump view`.

**Chosen**: `FileOrganizer` moves attachments into `Videos/` `Photos/` `Audio/` `Other/` by extension, after slackdump exits.

**Why**:
- The user explicitly asked for it. Constraint 5 (output should be human-grokkable) wins.
- We never overwrite — collisions get a `(<FILE_ID>)` suffix using slackdump's globally-unique IDs.
- The SQLite stays at the run-folder root, so `slackdump view` / `convert -f html` still work against it.
- Toggle in Settings (default on) — anyone who needs the native layout for round-tripping can turn it off.

The four-category split (`Videos` / `Photos` / `Audio` / `Other`) is the minimum that satisfies "I want to see all the photos at once" without becoming an extension-by-extension Cartesian explosion. PDFs, docs, archives, transcripts all land in `Other/` and that's fine.

### 6. SQLite via `sqlite3 -json` subprocess, not the SQLite3 C API

**Considered**: link against macOS's built-in `libsqlite3.tbd`, use prepared statements directly. Faster, no subprocess overhead.

**Chosen**: shell out to `/usr/bin/sqlite3 -json` per query.

**Why**:
- Three queries per chat export; each completes in milliseconds. Subprocess overhead is in the noise.
- `JSONDecoder` against typed Codable structs is dramatically simpler than C-API pointer juggling, prepared-statement lifecycles, and string-encoding contracts.
- `json_extract(CAST(DATA AS TEXT), '$.user')` lifts the user ID out of the message JSON blob in the SQL layer — would be tedious in C.
- Mocking SQLite for tests is impractical; mocking `render(messages:users:files:channels:…)` is trivial. Splitting I/O from formatting is what enables 100% test coverage on the renderer.

### 7. ChatExporter is a pure renderer + a thin I/O wrapper

**Pattern**: `ChatExporter.export(runFolder:…)` does I/O (SQLite queries + file write). `ChatExporter.render(messages:users:files:channels:…)` is pure — takes pre-loaded arrays, returns a `String`.

**Why**: every meaningful test is a `render(…)` test with synthetic input. Thread indentation, mention resolution, attachment listing, unknown-user fallback, HTML entity decoding — all 6 cases. The I/O path is exercised once by a smoke test that runs the actual `sqlite3` against a fixture archive (run manually before commits, not in CI).

### 8. Settings round-trip is backwards-compatible

Decoding `ArchiveOptions` uses `decodeIfPresent` for any field added after 1.0.0. Concretely:

```swift
self.organizeFiles = try c.decodeIfPresent(Bool.self, forKey: .organizeFiles) ?? true
```

**Why**: a user who installs the app, configures Settings, then upgrades to a version that added a new option shouldn't lose their existing config because the decoder strict-failed on a missing key. Default-`true`-on-absent gives them the new behavior without intervention.

### 9. Auto-backup on launch, even though slackdump owns its own state

**Considered**: skip backup entirely. Slackdump's data is in `~/Library/Caches/slackdump/` (encrypted, slackdump-owned), and our archive folders are user-visible in `~/Downloads/`. What's left to back up?

**Chosen**: zip `~/Library/Application Support/SlackSucker/` on every launch (debounced 5 min, 14-day retention).

**Why**:
- It's the PhantomLives standard (CLAUDE.md → auto-backup-on-launch). Every app that owns persistent user data ships this.
- The Application Support dir holds settings, run history, presets, and the channel cache. Losing any of those is annoying — losing the presets after building them up over months is genuinely painful.
- Slackdump's own creds are deliberately *not* backed up. Re-auth is one command; shipping encrypted credential blobs into the user's Downloads folder is the wrong default.

### 10. Post-processing pipeline is a sequence of independent passes (1.1)

Once the 1.0 baseline shipped, four post-archive enhancements landed
as a batch: orientation baking, metadata stripping, A/V transcription,
hash manifests. Decision: model each as a separate `Service` enum with
a pure `run(runFolder:…)` entry point, NOT a shared "post-processor"
framework with plugin protocols.

**Why a sequence of separate passes**:
- Each has different dependencies (`exiftool`, `ffmpeg`, `transcribe.py`,
  `CryptoKit`) and failure modes. A unified framework would have to
  paper over those differences, hiding important context from the user.
- Order matters between TWO of them (orientation must precede strip).
  Encoding that as a hardcoded sequence in `ArchiveRunner` is clearer
  than a topological sort with declared dependencies.
- Adding a new pass = drop a new `Services/<Name>.swift`, write the
  pure entry point, wire one `if request.<flag>` block. No framework
  to grok.

**Why a `<name>-log.txt` per pass instead of one combined log**:
- A user trying to debug "why didn't my photos rotate?" can `cat
  orient-log.txt` without paging through everything else. The runner's
  live log already has the cross-cutting view.
- Each pass's log file is the source of truth for that pass; the
  in-memory `Result` is just what the runner surfaces in the UI.

### 11. Bake orientation honestly — no ML inference (1.1)

The user asked: "can we automatically rotate images and videos so
they're the correct way (people)". The honest answer was *yes for
EXIF-flag-baking, no for content-aware inference*.

**What we deliver**:
- Photos: `CGImageSource` reads `kCGImagePropertyOrientation`. If non-1,
  `CIImage.oriented(forExifOrientation:)` rotates the pixel data, we
  re-encode via `CGImageDestination`, then reset Orientation=1.
- Videos: `ffmpeg -display_rotation 0 -metadata:s:v:0 rotate=0 -c copy`
  re-encodes (stream copy where possible) and drops the rotation tag.

**What we explicitly don't deliver**:
- ML-based "look at the picture and decide which way is up". Vision
  framework's face detection works on best-case single-face shots and
  fails on group photos, side profiles, abstract content, screenshots,
  and indoor scenes. Horizon detection via ML is a research-grade
  problem. The reliability ceiling on user content is too low.

The trade-off: the toggle is correctly named "Bake orientation", not
"Auto-rotate". Documented in both `USER_MANUAL.md` and `CHANGELOG.md`
that the screenshot / no-flag case is out of scope.

### 12. Single-pass multi-algorithm hashing (1.1)

Hash manifests support multiple algorithms (MD5 / SHA-1 / SHA-256).
Naïve implementation: three separate `FileHandle` reads, one per
algorithm.

**Chosen**: one `FileHandle.read(upToCount:)` loop, feed each chunk to
every selected hasher via `Data.withUnsafeBytes { raw in ... }`. Each
hasher's `.update(bufferPointer:)` is O(chunk-size); the read is what
dominates. A 1GB file gets read exactly once regardless of how many
algorithms the user picked.

**Why CryptoKit**:
- `Insecure.MD5` and `Insecure.SHA1` are right there. No need to link
  CommonCrypto, no `<CC_MD5_CTX>` lifecycle to manage.
- `SHA256()` matches the same `HashFunction` protocol — uniform call
  site (`update` / `finalize`).
- The `.Insecure` namespacing nudges callers toward SHA-256 by default;
  MD5 / SHA-1 remain available for cross-referencing legacy archives
  (Slack data export auditors, forensic catalogues).

### 13. Transcription doesn't bundle, by design (1.1)

The `transcribe/` PhantomLives subproject is a self-bootstrapping
Python script that creates a `.venv` and pulls multi-GB MLX-Whisper
weights on first run. Bundling all of that inside `SlackSucker.app`
would:
- Bloat the bundle from ~36MB to ~6GB.
- Break code signing — the `.venv` interpreter and pip-installed
  binaries fail `codesign --verify` because they have iCloud xattrs
  the moment they live anywhere under `~/Documents/`.
- Couple SlackSucker's release cadence to MLX-Whisper's. We'd have to
  rebuild every time the user upgraded their Python.

**Chosen**: resolve at runtime via `$SLACKSUCKER_TRANSCRIBE_BIN` →
PATH `transcribe` → sibling-checkout `transcribe/transcribe.py`. If
none of those exist, the live log shows `[transcribe] skipped — no
transcribe binary found` and the archive otherwise completes normally.

The user pays a one-time "check out the sibling repo" cost; in
exchange the integration stays loose and the Whisper deps live where
they should (the user's home, with the rest of their MLX models).

### 14. Per-session output override doesn't write to Settings (1.1)

The main-screen "Export folder" card has a "Choose…" button. Pressing
it does NOT update `settings.json` — it only sets a `@State` variable
in `RootView` that overrides for the current session.

**Why**:
- The user explicitly asked for this — "settings definition will
  remain the default unless changed in settings". That's a deliberate
  separation: Settings is for the persistent default; main-screen is
  for "just this run, just this session".
- Mixing "configure once" and "tweak per session" into the same
  control creates surprise — change the main-screen path for a
  one-off export and your default silently moves with it.
- The "Reset" button next to the override returns to the Settings
  default, so the user always has a one-click path back to home base.

### 15. `install.sh` ships alongside `build-app.sh`

**Why**:
- `/Applications/<App>.app` is the only path that keeps TCC, Launch Services, Spotlight, and iCloud's File Provider all happy. Running from the project tree breaks all four in subtle ways (duplicate permission entries, phantom ` 2.app` clones, xattr-induced codesign failures).
- The full rationale is in CLAUDE.md → "install.sh standard for `.app` subprojects". This is now a PhantomLives convention; SlackSucker's `install.sh` is the reference implementation.

## What we'd do differently in v2

- **`Chat/` for workspace-wide archives.** Produce one `.txt` per channel under `Chat/<channel-name>.txt`. Currently we skip the whole thing. The renderer is already parameterized by channel; just loop over CHANNEL rows.
- **Inline file paths in `Chat/<scope>.txt`.** Right now attached files appear as `[file] <filename>`. Including the resolved `Photos/<file>` path would let `cat Chat/foo.txt` give you everything in one view.
- **Slack message edits.** `MESSAGE.DATA.edited.ts` exists in Slack's JSON. We don't surface it. Would be a nice annotation in the transcript.
- **Reactions.** Same — `MESSAGE.DATA.reactions[]` carries `name` + `users[]`. Could append `[👍 ×3]` to each message.
- **Native channel-picker keyboard nav.** The combobox currently routes Enter to "pick highlighted" but ⬆/⬇ don't move the highlight yet. SwiftUI focus management for inline dropdowns is finicky.

None of these are blocking. They'd each be a focused PR.
