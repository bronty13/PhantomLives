# ElectronicDetective

Native macOS recreation of the 1979 Ideal Toy Corp. tabletop game **Electronic Detective** — the angled brown LED console, the 20-card suspect rolodex, the four-section Case Fact Sheet pad, and the period audio cues (3 bongs / gunshot / siren / dirge). Personal-use only.

## Build & run

```
./build-app.sh           # → ElectronicDetective.app in the project root
./run-tests.sh           # full XCTest suite
```

Requires full Xcode (not just Command Line Tools), `xcodegen` (`brew install xcodegen`), and an internet connection for the first build (GRDB is fetched via SwiftPM). Targets macOS 14.0+.

## Versioning

`build-app.sh` derives the short version from git (`1.0.<commit-count>`) and the build number from `<count>.<short-sha>`, stamping them into the **built bundle's** `Info.plist` while it's still in `/tmp` (signing happens there too — see below). The source `Info.plist` carries `0.0.0 / 0.unknown` placeholders so the working tree stays clean.

### iCloud Drive and codesign

The script signs the bundle while it's still in `/tmp` and `ditto`s the signed bundle into the project directory afterwards. This sidesteps macOS's file-provider re-adding `com.apple.FinderInfo` to bundles under iCloud-synced folders between `xattr -cr` and `codesign` — which previously produced "resource fork, Finder information, or similar detritus not allowed" failures and unsigned bundles that hung on launch under Gatekeeper.

## How to play

Press the on-screen **ON** key — the LED prompts:

1. `PL?` — type player count (`1`–`4`) + **ENTER**
2. `DIF?` — type difficulty (`1` = Master Detective, `2` = Sleuth, `3` = Gumshoe) + **ENTER**
3. `BDY <loc>` — the body was found at this location; record it on your pad.

During your turn:
- **SUSPECT** + suspect id (`1`–`20`) + **ENTER** → LED shows where that suspect was (e.g. `ART`, `DOC`).
- **PRIVATE Q** + suspect id + **ENTER** → if that suspect was at a weapon's location, LED shows `ODD` / `EVEN` (the parity of the murderer's id); otherwise `IDK`. Bounded by your turn's PQ budget (1–3 depending on difficulty).
- **I ACCUSE** + suspect id + **ENTER** → siren if right (`CASE SOLVED`); gunshot if wrong — you're out of the game.
- **END** → pass the console. In multiplayer the screen blacks out until the next player taps.

Or just tap a card in the rolodex on the right for a quick action menu.

## File layout

```
Sources/ElectronicDetective/
├── App/             entry point, AppState, AppSettings, Info.plist, entitlements, Version
├── Models/          Sex/IDParity, Suspect, SuspectRoster, Location, Weapon, Difficulty,
│                    GameCase, PlayerNotepad, GameSession
├── Engine/          CaseGenerator (constraint-respecting), Interrogator, Accuser,
│                    ConsoleProtocol (ConsoleKey, LEDLine)
├── Audio/           SoundBank (AVAudioEngine) + Synth (procedural bong / click / gunshot /
│                    siren / dirge); no shipped audio assets
├── Services/        DatabaseService (GRDB SQLite + migrations), BackupService
│                    (14-day rolling backup zips), AssetResolver (runtime user-asset lookup)
├── Views/
│   ├── Console/     ConsoleView, LEDDisplayView, KeypadView, KeyButton, ConsoleViewModel
│   ├── Rolodex/     SuspectRolodexView (2×10 grid), SuspectCardView
│   ├── Notepad/     CaseFactSheetView (editable, 4 sections)
│   ├── Rules/       RulesBookletView (paginated, PDFKit + NSImage)
│   ├── Setup/       HotSeatHandoffView (blackout curtain between turns)
│   ├── GameOver/    VerdictView (post-game reveal overlay)
│   ├── History/     GameHistoryView (Table of past games from session_history)
│   ├── Settings/    SettingsView
│   └── ContentView.swift
└── Resources/       Assets.xcassets (AppIcon)
```

## Persistent state and outputs

| What | Where |
|---|---|
| In-flight game + history (SQLite) | `~/Library/Application Support/ElectronicDetective/database.sqlite` |
| Auto-backup zips (14-day retention) | `~/Downloads/ElectronicDetective backup/` |
| User asset overrides | `~/Documents/ElectronicDetective Assets/` |
| Settings | `UserDefaults` under the `ED.*` key prefix |

The in-flight game saves on every mutation, so a force-quit or system restart drops you straight back into the same turn. Finished games append to `session_history` and surface in the **History** sheet (toolbar, top-right).

## User assets

Drop these into `~/Documents/ElectronicDetective Assets/`:

| Folder | Files | Notes |
|---|---|---|
| `suspects/` | `suspect_01.png` … `suspect_20.png` | One image per card. Any aspect ratio. |
| `manual/` | `page_01.png` … `page_NN.png` (or `.pdf`) | Browseable in the Rules booklet. |
| `box/` | `front.png`, `back.png` | Optional. |
| `audio/` | `bong.wav`, `gunshot.wav`, `siren.wav`, `dirge.wav`, `key.wav` | Replaces any cue. Missing files fall back to synthesis. |
| `notepad/` | `sheet.png` | Optional pad-background overlay. |

The directory and its `README.txt` are created on first launch. Missing files fall back to vector placeholders or procedural audio.

## Suspect cast

`Sources/ElectronicDetective/Models/SuspectRoster.swift` ships placeholder names (`Suspect 01` … `Suspect 20`) preserving the original id → sex (1–10 male, 11–20 female) and id-parity mappings. The engine treats `name` and `occupation` as opaque display strings, so substituting the canonical cast from your copy of the rules is a one-file edit.

## Tests

`./run-tests.sh` (28 tests):
- `CaseGeneratorTests` — 200-case validity sweep (distribution, sex caps, parity rule, murderer/body/weapon placement), reproducibility, speed.
- `InterrogatorTests` — truth / IDK / dead rules, fingerprint parity.
- `AccuserTests` — correct / wrong / final-wrong / no-double-accuse.
- `TurnFlowTests` — solo no-curtain, multiplayer curtain, eliminated-seat skipping, auto-advance on wrong, end-of-game no-curtain.
- `DatabaseServiceTests` — round-trip save/load, clear, history append, idempotence, in-progress filtering, reopen.
- `BackupServiceTests` — target-directory auto-create, prefix-scoped retention trim, list ordering, retention=0.

## Status

All five milestones from the plan are landed. The app is fully playable solo or 1–4 hot-seat; resumes in place; auto-backs-up; and surfaces game history. See `CHANGELOG.md` for per-milestone notes.
