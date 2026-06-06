# Quizzer

**A lightweight, portable creator that deploys self-contained, branded activities
to any browser — desktop or mobile, online or offline, no server required.**

Quizzer makes two kinds of activity from one codebase:

1. **Creator** — a single-page app you run in your browser to create, edit, brand,
   import, export, and **deploy** quizzes **and Spin-the-Wheels**. All your work is
   stored locally in the browser (IndexedDB); nothing is uploaded anywhere.
2. **Quiz player** — what "Deploy" produces for a quiz: a self-contained quiz a
   respondent opens in any browser. It runs entirely client-side (works from a
   `file://` URL, offline), grades itself, shows a PASS/FAIL summary, and can issue a
   class-style **PDF completion certificate**.
3. **Spin-the-Wheel player** — a fun, non-graded activity (its own **Wheels** section
   in the creator): a branded, animated prize wheel with sound, an optional spins
   limit, a big result reveal, and a **PDF that memorializes the win**. Same offline,
   single-file portability.

Runs anywhere with a modern browser: macOS, Windows, Linux, ChromeOS, iOS Safari,
Android Chrome.

---

## Quick start

```bash
npm install          # first time only
npm run dev          # creator dev server (also builds both player templates) → http://localhost:1500
npm run build        # production build → dist/index.html (the creator, single file)
npm test             # vitest (80 tests)
npm run typecheck    # tsc --noEmit
```

To use the creator without a dev server, just `npm run build` and open
`dist/index.html` — it is a single self-contained file you can double-click.

### Developer commands

| Command | What it does |
|---|---|
| `npm run dev` | Ensures both player templates are fresh, then starts the creator dev server. |
| `npm run dev:player` | Runs the **quiz player** standalone (built-in demo quiz) on :1501. |
| `npm run dev:wheel` | Runs the **wheel player** standalone (built-in demo wheel) on :1502. |
| `npm run build` | `build:player → embed:player → build:wheel → embed:wheel → build:creator`. **Always use this** — never `build:creator` alone. |
| `npm run build:player` / `build:wheel` | Builds a player bundle to `dist-player/` / `dist-wheel/`. |
| `npm run embed:player` / `embed:wheel` | Copies a built player into its `generated/*Template.ts`. |
| `npm run restore:stubs` / `check:stubs` | Reset both committed template stubs / fail if either is a built blob. Run before committing. |
| `npm test` / `npm run typecheck` | Tests / type-check. |

---

## How deployment works (the two-bundle architecture)

The creator has no server, yet "Deploy" must emit a *separate*, finished player
file at runtime in the browser. So Quizzer builds **two** bundles:

```
src/player  ──vite──▶ dist-player/index.html ──embed──▶ src/creator/generated/playerTemplate.ts
                                                              │ (imported as a string)
src/creator ──vite──▶ dist/index.html ◀───────────────────────┘
```

- The **player** is a self-contained single-file app that reads its quiz from a
  global `window.__QUIZ__` (never `fetch` — that breaks under `file://`).
- `scripts/embed-player.mjs` turns the built player HTML into a string the creator
  imports. At deploy time the creator injects the quiz + branding into that template
  and triggers a download.
- `src/creator/generated/playerTemplate.ts` is a **committed stub**; `npm run build`
  regenerates it from the real build. (Don't commit its built form — run
  `npm run restore:stubs` first.)

The **Spin-the-Wheel** activity adds a *second* player bundle on the same rail
(`src/wheel-player ─▶ dist-wheel/index.html ─▶ wheelTemplate.ts`), so a deployed wheel
ships only wheel code and a deployed quiz ships only quiz code. There are therefore
**two** committed stubs — `restore:stubs` / `check:stubs` manage both.

This ordering is enforced by the single `build` script (`build:creator` runs last).

### Deploy formats (chosen per deploy)

- **Single HTML file** — everything (quiz, branding, logo, fonts, player code, the
  PDF engine) inlined into one `.html`. Email it, host it, or open it offline.
- **Zip** — `index.html` + an `assets/` folder. Large intro videos are kept as
  separate files instead of bloating the HTML. Unzip, then open `index.html`.

Both formats use the **same** player; only how `window.__QUIZ__` is populated
differs (inline `<script>` vs. a classic `<script src="./data.js">`).

---

## Question types & grading

All grading happens client-side in the deployed quiz (`src/shared/grading.ts`, the
single source of truth shared by the creator's preview and the player):

| Type | Grading |
|---|---|
| **True / False** | Exact match. |
| **Multiple Choice** | One correct choice; choices can be randomized. |
| **Multiple Answer** | Exact set match — **all-or-nothing** (no partial credit). |
| **Fill in the Blank** | 1+ blanks, each with 1+ accepted answers; case-optional, trimmed, whitespace-collapsed. **Proportional** credit across blanks. |
| **Short Answer** | *Keyword* mode (needs N keyword matches) or *Manual*. |

**Manual short-answer:** a deployed offline quiz has no human grader, so manual
questions are **auto-credited** and labelled "self-graded" in the summary.

Every question can also carry an **optional image**, shown between the question text
and the answer choices.

---

## Spin the Wheel

A second activity type, in the creator's **Wheels** section — a customizable prize
wheel, not a graded quiz. Configure a title, a description (default *"Spin the Wheel
for a Prize."*), an optional image/video, **1–30 labeled choices**, a spins-permitted
limit (`0` = unlimited), the default sound state, and how many results the exported
PDF lists. It reuses your branding profiles.

The deployed wheel is a self-contained, offline, mobile-friendly SPA: a branded
**canvas wheel** that spins several turns and decelerates onto a sector, synthesized
**tick + win-chime sound** (a toggle, default on, and silent under
`prefers-reduced-motion`, which also skips the long spin), an enforced spins limit, a
big animated **result reveal**, and a **"Download Result (PDF)"** memorializing the
win(s).

**Fair by default, riggable on purpose.** Choices are equal-odds out of the box. Flip
**Advanced odds** in the editor to give each choice a relative `weight` (`0` = never
lands). The sectors always look equal-sized — only the landing probability changes.

## Branding & fonts

Reusable branding profiles carry five colors, a logo, and a font, applied to the
creator and to **every page** of the deployed quiz.

- **Built-in fonts** (10) use curated cross-platform font stacks — zero weight, fully
  offline, but they fall back to the device's nearest system font.
- **Uploaded TTF** fonts are embedded as base64 `@font-face` for pixel-identical
  rendering on any device. Upload a TTF when you need guaranteed-consistent branding.

---

## Answer secrecy — read this

Because grading is 100% client-side, the correct answers must exist inside the
deployed file. Quizzer **obfuscates** the answer key (base64 + XOR) so it doesn't
appear in plain View-Source, **but this is deterrence, not security** — a determined
respondent can recover the answers. Use Quizzer for training, practice, and
low-stakes assessment, not for anything where answer leakage truly matters.

---

## Output location

Deployed quizzes and exported bundles download through your browser. Set your
browser's download folder to **`~/Downloads/Quizzer/`** to match the PhantomLives
convention. Internal creator data lives in the browser's IndexedDB.

---

## Project structure

```
src/shared/      model, grading, obfuscation, payload(s), spin math, fonts, branding, PDFs (used by all apps)
src/player/      the deployed quiz app (intro → questions → feedback → summary → certificate)
src/wheel-player/  the deployed Spin-the-Wheel app (canvas wheel, Web Audio, result PDF)
src/creator/     the authoring app (quizzes + wheels lists/editors, branding, settings, deploy)
src/creator/deploy/   inject payload, single-file + zip builders, downloads, quiz + wheel orchestrators
scripts/         embed-/ensure-{player,wheel} build glue, restore-/check-stubs guardrails
tests/           vitest suites (grading, obfuscation, payloads, spin math, deploy, serialize, PDFs, integration)
```

---

## Notes for PhantomLives

Quizzer is a **pure browser SPA** — the macOS-app conventions (`build-app.sh`,
`install.sh`, auto-backup-on-launch, `NavigationSplitView`, SQL-migration
immutability) do not apply. Release hygiene (version in `package.json`, CHANGELOG,
README/USER_MANUAL, tests) does.
