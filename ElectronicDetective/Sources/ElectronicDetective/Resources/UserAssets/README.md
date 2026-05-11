# UserAssets

Personal scans, photographs, and audio recordings that recreate the look and feel of the original console. Files in this directory are **gitignored** so they never leave your machine.

The app loads whatever is present and falls back to vector placeholders for anything missing — you can populate this directory incrementally and the app stays playable throughout.

## Naming

| Folder | File names | Notes |
|---|---|---|
| `suspects/` | `suspect_01.png` … `suspect_20.png` | One image per card (IDs 1–10 male, 11–20 female). Any aspect ratio; the rolodex pads to a card frame. |
| `manual/` | `page_01.png` … `page_NN.png` (or `.pdf`) | Scanned rules pages; rendered in the in-app booklet viewer in order. |
| `box/` | `front.png`, `back.png` | Optional box artwork shown on the About / splash. |
| `audio/` | `bong.wav`, `gunshot.wav`, `siren.wav`, `dirge.wav`, `key.wav` | Cue replacements. Anything missing is synthesized at runtime by `SoundBank`. |
| `notepad/` | `sheet.png` | Optional background overlay for the Case Fact Sheet view. |

## Suspect names

The factual cast list (20 names) lives in `Sources/ElectronicDetective/Models/SuspectRoster.swift`. The shipped version uses generic placeholders (`Suspect 01` … `Suspect 20`) preserving the male/female and odd/even ID assignments. Edit that one file locally to substitute the canonical names from your copy of the rules.
