# Changelog

## Unreleased — M5 persistence, backup, release polish

- `Services/DatabaseService.swift`: GRDB-backed SQLite at `~/Library/Application Support/ElectronicDetective/database.sqlite`. Two tables — `current_session` (in-flight `GameSession` as JSON) and `session_history` (terminal-outcome rows). Append-only migrator; idempotent history append; test seam via `init(path:)`.
- `Services/BackupService.swift`: launch-time zip of the support directory into `~/Downloads/ElectronicDetective backup/`. 14-day retention (configurable), prefix-scoped trim (`ElectronicDetective-*.zip` only, leaves unrelated zips alone), 5-minute debounce.
- `AppState` integration: loads any in-flight game on launch and dismisses the verdict overlay if the previous run ended; saves the session on every mutation via `didSet`; appends to history when a game reaches `solved` / `allWrong`; new `forgetCurrentSession()` for the Settings reset button.
- `Views/History/GameHistoryView.swift`: paginated `Table` of every finished game (newest first) with date, outcome, difficulty, player count, and murderer. Opens from a new **History** toolbar button.
- `SettingsView` expansions: Backup section (auto-toggle, retention stepper, last-backup readout, "Run backup now", "Open backup folder") and Session section ("Forget current game" destructive button).
- `DatabaseServiceTests` (6 tests): round-trip, clear, history append, idempotence, in-progress filtering, reopen-sees-data.
- `BackupServiceTests` (4 tests): target-directory auto-create, prefix-scoped retention trim, list ordering newest-first, `retentionDays=0` short-circuit.
- README rewritten to document play flow (PL? → DIF? → BDY), file layout, persistent paths, asset conventions, and the iCloud-Drive / codesign workaround.

Status after M5: 28 tests green; the app is fully playable solo or 1–4 hot-seat; the in-flight game persists across launches; finished games accumulate in History; backups roll daily with 14-day retention.

## Unreleased — M4 hot-seat 2–4 players

- ON now drives the original game's prompt sequence over the LED: `PL?` (player count, 1–4) → `DIF?` (difficulty, 1–3) → game starts and the LED announces `BDY <loc>` for the body location. Function keys (SUSPECT / PRIVATE Q / I ACCUSE / END) display `OFF` until a game is in flight.
- `Views/Setup/HotSeatHandoffView.swift`: full-window black curtain shown between turns in 2+ player games. Tap-anywhere dismiss.
- `AppState.handoffPending` flag drives the curtain. `endTurn()` raises it in multi-player; wrong accusations auto-advance to the next active seat AND raise it (no more stranded eliminated players holding the desk). Solo games never raise the curtain. Final wrong-accusation that ends the game skips the curtain in favour of the verdict overlay.
- `Tests/ElectronicDetectiveTests/TurnFlowTests.swift`: 5 new tests covering solo no-curtain, multiplayer curtain, eliminated-seat skipping, wrong-accusation auto-advance, and end-of-game no-curtain. All 18 tests green.

## Unreleased — M3 audio, verdict screen, strict transcription mode

- `Audio/SoundBank.swift` + `Synth` enum: `AVAudioEngine`-backed bank with five synthesized cues (`bong`, `keyClick`, `gunshot`, `siren`, `dirge`) generated procedurally from sine + noise envelopes — no shipped audio assets. User-supplied recordings in `audio/` take precedence per cue when present.
- ON now actually starts a default solo gumshoe game (proper setup flow lands in M4). Every keypress fires `key`; ON layers `bong`; correct accusation triggers `siren`; wrong fires `gunshot`; all-wrong ends with `dirge`.
- `Views/GameOver/VerdictView.swift`: full-window overlay on outcome transition. Shows headline (`CASE SOLVED` / `CASE COLD`), murderer reveal (name, occupation, location, weapons, fingerprint parity), and New-Game / Close actions. Honors `Settings.revealOnLoss`.
- `AppState` gains `playCue(_:)`, mirrors `audioEnabled` + `keyClickEnabled` from `AppSettings` to `SoundBank` on every play so toggles take effect live, and tracks `verdictDismissed` so closing the overlay leaves the final notepad visible.
- Strict transcription mode (already wired in M1) now end-to-end exercisable: in `.strict`, console answers display on the LED but `AppState.autoRecord` is a no-op, so the player must type into the on-screen pad themselves.

## Unreleased — M2 rolodex, notepad, rules, asset resolver

- `AssetResolver` service: runtime asset lookup from `~/Documents/ElectronicDetective Assets/` (auto-created on first launch with a README). Suspect cards, manual pages, box art, audio cues, and the notepad overlay all picked up without rebuild.
- `SuspectRolodexView` + `SuspectCardView`: 2-column grid of all 20 suspects with placeholder portraits when no scan is present. Tapping a card opens an interrogation popover (WHERE? / FINGERPRINT?) that routes to the engine.
- `CaseFactSheetView` (full): editable four-section pad — Murder Facts (sex/caliber/parity/location pickers), Who Was Where? (per-suspect location picker, auto-filled in `.auto` mode), Who Said What? (per-suspect notes), Who Did It? (accusation picker).
- `RulesBookletView`: paginated PDF/image viewer with prev/next + "Reveal in Finder" empty state.
- ContentView reorganised: notepad | console | rolodex with a "Rules" toolbar button; below-console briefing strip shows current player, difficulty, PQ budget, and outcome.
- SettingsView: new "User assets" section with path readout, Reveal in Finder, and Refresh actions.

## Unreleased — M1 scaffold

- Project skeleton: XcodeGen `project.yml`, `build-app.sh`, `run-tests.sh`, `.gitignore`, README.
- App layer: `ElectronicDetectiveApp`, `AppState`, `AppSettings`, `Info.plist`, entitlements.
- Domain models: `Sex`, `Suspect`, `SuspectRoster`, `Location`, `Weapon`, `Difficulty`, `GameCase`, `PlayerNotepad`, `GameSession`.
- Engine: `CaseGenerator` (constraint-respecting), `Interrogator` (truth / lie / IDK rules), `Accuser` (first-wrong elimination), `ConsoleProtocol`.
- Views: skeletal `ContentView`, `ConsoleView`, `LEDDisplayView`, `KeypadView`, `KeyButton`, minimal `CaseFactSheetView`.
- Tests: `CaseGeneratorTests`, `InterrogatorTests`, `AccuserTests`.
