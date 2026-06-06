# Quizzer

**A lightweight, portable quiz creator that deploys self-contained, branded quizzes
to any browser — desktop or mobile, online or offline, no server required.**

Quizzer is two products built from one codebase:

1. **Creator** — a single-page app you run in your browser to create, edit, brand,
   import, export, and **deploy** quizzes. All your work is stored locally in the
   browser (IndexedDB); nothing is uploaded anywhere.
2. **Player** — what "Deploy Quiz" produces: a self-contained quiz a respondent
   opens in any browser. It runs entirely client-side (works from a `file://` URL,
   offline), grades itself, shows a PASS/FAIL summary, and can issue a class-style
   **PDF completion certificate**.

Runs anywhere with a modern browser: macOS, Windows, Linux, ChromeOS, iOS Safari,
Android Chrome.

---

## Quick start

```bash
npm install          # first time only
npm run dev          # creator dev server (also builds the player template) → http://localhost:1500
npm run build        # production build → dist/index.html (the creator, single file)
npm test             # vitest (44 tests)
npm run typecheck    # tsc --noEmit
```

To use the creator without a dev server, just `npm run build` and open
`dist/index.html` — it is a single self-contained file you can double-click.

### Developer commands

| Command | What it does |
|---|---|
| `npm run dev` | Ensures the player template is fresh, then starts the creator dev server. |
| `npm run dev:player` | Runs the **player** standalone (with a built-in demo quiz) on :1501. |
| `npm run build` | `build:player` → `embed:player` → `build:creator`. **Always use this** — never `build:creator` alone. |
| `npm run build:player` | Builds the player to `dist-player/index.html`. |
| `npm run embed:player` | Copies the built player into `src/creator/generated/playerTemplate.ts`. |
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
  regenerates it from the real build. (Don't commit its built form.)

This ordering is enforced by the single `build` script — see `docs`-style notes in
`CHANGELOG.md`.

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
src/shared/    model, grading, obfuscation, payload, fonts, branding, certificate (used by both apps)
src/player/    the deployed quiz app (intro → questions → feedback → summary → certificate)
src/creator/   the authoring app (quiz list, editor, branding manager, settings, deploy)
src/creator/deploy/   inject payload, single-file + zip builders, downloads
scripts/       embed-player / ensure-player build glue
tests/         vitest suites (grading, obfuscation, payload, deploy, serialize, certificate, sanitize, integration)
```

---

## Notes for PhantomLives

Quizzer is a **pure browser SPA** — the macOS-app conventions (`build-app.sh`,
`install.sh`, auto-backup-on-launch, `NavigationSplitView`, SQL-migration
immutability) do not apply. Release hygiene (version in `package.json`, CHANGELOG,
README/USER_MANUAL, tests) does.
