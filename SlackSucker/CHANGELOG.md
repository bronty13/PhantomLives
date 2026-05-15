# SlackSucker changelog

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
