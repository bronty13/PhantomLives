# PurpleTracker

Native macOS app to track work units ("Matters") with a strict daily-resetting Matter ID, type-color coding, attachments stored as BLOBs (with MD5 / SHA1 / SHA256 integrity hashes), per-Matter time tracking, cadenced repeating activities, and PhantomLives-standard auto-backup-on-launch.

- **Highlights:** large-and-copyable Matter IDs · **prominent P1–P5 priority** · type-colored matters · per-Matter timer + global weekly timesheet · attachments-as-BLOBs with hash verification · cadenced repeating activities · markdown editors with spellcheck · auto-backup-on-launch · **People roster integration** (ADP UserFeed CSV import + auto-import on launch) · **Requestor + 5 Internal + 5 External Interested Party slots** on every Matter · **Initiatives + Goals tagging** · multi-format export (md / pdf / docx / clipboard) · cross-Matter search by title, content, Matter ID, or person.

Part of [PhantomLives](https://github.com/bronty13/PhantomLives).

## Quick start

```bash
brew install xcodegen
./build-app.sh        # produces ./PurpleTracker.app
./run-tests.sh        # runs the XCTest suite
open PurpleTracker.app
```

Requires Xcode 16, macOS 14 (Sonoma) or later.

## Highlights

- **Matter ID** every record — `YYYY-MM-DD-#####`, daily-resetting, allocated transactionally so concurrent inserts can never collide. Always rendered large + monospaced with a one-click Copy button.
- **Priority** — every Matter carries a fixed-set priority (`P1 Critical`, `P2 High`, `P3 Medium`, `P4 Low`, `P5 Tech Debt`), shown as a color-coded pill in the detail header and a `P#` badge on every list row. New Matters default to **P3 Medium**; cadenced successors carry priority forward.
- **Initiatives & Goals** — tag any Matter with one or more configurable Initiatives (strategic) and Goals (team/quarterly). Manage the master lists under Settings → Initiatives and Settings → Goals. Tags are many-to-many and carry forward on cadenced spawns; reports include them.
- **Configurable types** with color coding — header strip and row leading bar are tinted by type so you can feel the type at a glance. Defaults: Client Request, SSAE/SOC Audit, Client Audit, External Audit, DR/BCP, Assurance, Policies and Standards, Investigation, Legal, HR, Finance, AI Enablement, Staff, Cadenced Activities.
- **Multi-tier status lifecycle** — `New → In-Progress → Complete → Post-Mortem → Closed`. Auto-bumps from New to In-Progress the first time a timer runs. Reorderable / renamable.
- **Cadenced Activities** — cadence kinds: Daily, Weekly, Bi-weekly, Monthly, Quarterly, Semi-annually, Annually, Custom (every N days). Closing a cadenced Matter spawns the next instance with `due_at` shifted forward.
- **Attachments** — files ingested into the SQLite DB as BLOBs with MD5 + SHA1 + SHA256. SHA1 is verified on every access; mismatch raises a banner and persists a flag.
- **Time tracking** — single global active timer (no double-billing), persists across app quit, per-Matter detail + global cross-Matter weekly timesheet (ISO weeks).
- **Markdown editors** with continuous spellcheck for Description, Notes, Resolution, and Lessons Learned.
- **External references** — three configurable label / number / URL slots (defaults: `defi SUPPORT (SNOW)`, `Azure DevOps (ADO)`, `Client Reference`) with launch buttons.
- **People roster** — daily ADP IMP UserFeed (`~/Downloads/ADP_IMP_UserFeed_YYYY-MM-DD.csv`) imported into a `person` table keyed on Associate ID. Auto-imports the newest file on launch (toggle in Settings → People); re-imports are filename-deduped.
- **Requestor + Interested Parties** — every Matter has a Requestor and five Interested Party slots (lookup over the People roster) plus five External Interested Party slots (free text for non-employees). The matter list shows a `person.2` badge with a count when any slot is set; the search box matches Requestor / IP names too.
- **File-store paths** — primary defaults to `~/Library/CloudStorage/OneDrive-defiSOLUTIONS/{year}/{YYYY-MM-DD} {Title}`, secondary to `~/Downloads/PurpleTracker/{Title}`. "Create" mkdir-p's; "Reveal" opens in Finder.
- **Exports** — Markdown, PDF, and Word `.docx`, plus copy-to-clipboard. The exported brief includes the Requestor and both IP lists. "Copy Brief" puts `Matter ID • Title • Date Opened • Status` on the pasteboard.
- **Auto-backup-on-launch** — PhantomLives standard. Default `~/Downloads/PurpleTracker backup/`, 30-day retention, debounced, with verify and restore. Settings → Backup is the control panel.

## Where things live

| Thing | Path |
|---|---|
| Database, attachments BLOBs | `~/Library/Application Support/PurpleTracker/purpletracker.sqlite` |
| Settings | `~/Library/Application Support/PurpleTracker/settings.json` |
| Backups | `~/Downloads/PurpleTracker backup/PurpleTracker-YYYY-MM-DD-HHmmss.zip` |
| Exports | `~/Downloads/PurpleTracker/<MatterID> <Title>.<ext>` |

All defaults are user-overridable in Settings.

See `USER_MANUAL.md` for day-to-day workflows, `INSTALL.md` for the build chain, and `HANDOFF.md` for the architecture overview.
