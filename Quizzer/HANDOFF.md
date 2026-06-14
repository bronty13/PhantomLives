# Quizzer — Architecture Handoff

The canonical architecture snapshot. Read this before non-trivial changes. For the
*why* behind the decisions, see `DESIGN.md`; for usage, `README.md` / `USER_MANUAL.md`.

## What it is

One **creator** plus **two** deployable player bundles (two activity types) from one
codebase:

- **Creator** (`src/creator/`) — a browser SPA you run to author **quizzes** and
  **spin-the-wheels**. No server; data lives in the browser's IndexedDB. Built to
  `dist/index.html` (single file).
- **Player** (`src/player/`) — the deployed **quiz** a respondent opens. Self-contained,
  client-side-graded, runs offline / under `file://`. Built to `dist-player/index.html`.
- **Wheel player** (`src/wheel-player/`) — the deployed **Spin-the-Wheel** activity
  (non-graded). Self-contained canvas wheel + Web Audio + result PDF. Built to
  `dist-wheel/index.html`. A *separate* bundle so each deployed file stays lean — a
  wheel ships no grading/obfuscation code; a quiz ships no canvas/audio code.

All are bundled to a single self-contained HTML by `vite-plugin-singlefile`
(everything inlined; the lone `<script type="module">` is inline, which is the only
module form that runs under `file://`).

## The two-bundle deploy pipeline (the crux)

The creator has no server, yet "Deploy" must emit a finished player file at runtime.
So the player's built HTML is embedded into the creator as a string constant:

```
src/player ─▶ dist-player/index.html ─(embed-player.mjs)▶ src/creator/generated/playerTemplate.ts
                                                                  │ imported as PLAYER_TEMPLATE
src/creator + PLAYER_TEMPLATE ─▶ dist/index.html
```

The **wheel** has its own parallel rail (`src/wheel-player ─▶ dist-wheel/index.html
─(embed-wheel.mjs)▶ wheelTemplate.ts`, imported as `WHEEL_TEMPLATE`). The deploy layer
is generalized: `injectScript`, `externalize*`, and `packZip` (`buildZip.ts`) serve
both; the creator picks the template by activity kind (`deploy/index.ts` for quizzes,
`deploy/wheel.ts` for wheels).

Build order is load-bearing and enforced by the single `npm run build` script:
`build:player → embed:player → build:wheel → embed:wheel → build:creator`. **`build:creator`
must stay last** (it imports both templates). **Never run `build:creator` alone.**

At deploy time the creator replaces the `<!--QUIZ_PAYLOAD-->` marker in the template:

- **Single `.html`** — inline `<script>window.__QUIZ__=…</script>` (assets as base64
  data-URIs), injected *before* the player's module script.
- **`.zip`** — marker becomes `<script src="./data.js"></script>` (classic script,
  works under `file://`); `data.js` sets `window.__QUIZ__`; large assets are written
  to `assets/` and referenced by relative path.

The player is **format-agnostic**: it always reads `window.__QUIZ__` and resolves
each `AssetRef` (`{kind:'inline',dataUri}` or `{kind:'file',path}`) to an element
`src`. Never `fetch`.

### ⚠️ The committed-stub gotcha (now TWO stubs)

`src/creator/generated/playerTemplate.ts` **and** `wheelTemplate.ts` are **committed
~500-byte stubs** (valid HTML with the marker, so `vite dev`/`tsc` resolve on a fresh
checkout). `npm run build` overwrites **both** locally with the real ~900 KB builds.
**Restore both stubs before committing** — never commit a built blob. Use
`npm run restore:stubs` to reset both, and `npm run check:stubs` to fail if either is
left as a blob (run it before committing). `scripts/ensure-{player,wheel}.mjs` rebuild
the templates for `npm run dev` when stale.

## File map

```
src/shared/        single source of truth, imported by BOTH apps
  model.ts         Quiz / Wheel / Branding / GlobalSettings / Question union / AssetRef
  grading.ts       pure graders per type + normalize() + gradeQuiz()
  obfuscate.ts     base64+XOR answer-key scramble (deterrence, not security)
  payload.ts       buildPayload (strip+obfuscate answers) / resolveQuestions (player)
  wheelPayload.ts  buildWheelPayload (NO obfuscation — wheel choices are public)
  branding.ts      Branding → CSS vars + @font-face
  fonts.ts         10 built-in font stacks + custom-TTF @font-face
  certificate.ts   jsPDF quiz completion certificate
  wheelResult.ts   jsPDF spin-result memorial PDF
  sanitize.ts      DOMPurify wrapper for WYSIWYG HTML
  assets.ts        resolveAsset / size + inline-threshold
  dataurl.ts       data-URI ⇄ bytes + jsonForScript (JSON-in-HTML escaping)
  factory.ts       new entity factories + demoBundle() / demoWheel()
  util.ts          shuffle / formatDuration / parseDuration / slugify

src/player/        deployed quiz
  bootstrap.ts     read window.__QUIZ__ (dev fallback = demoBundle) → resolve questions
  App.tsx          phase machine: intro → quiz → summary; attempts; timer
  flow/            IntroScreen, Timer, QuestionView, SummaryScreen, BrandBar, RichText
  attempts.ts      per-quiz attempt count (localStorage + in-memory fallback)

src/wheel-player/  deployed Spin-the-Wheel (non-graded)
  bootstrap.ts     read window.__QUIZ__ as a WheelDeployPayload (dev fallback = demoWheel)
  App.tsx          brandbar, title, description, media, SpinWheel, result reveal, PDF
  SpinWheel.tsx    canvas wheel + requestAnimationFrame spin + tick sounds
  spinMath.ts      PURE: pickWinner (weighted) / targetAngle / landedIndex / crossings
  sound.ts         Web Audio synthesized ticks + win chime (no asset files)
  spins.ts         per-deploy spins-used count, scoped by generatedAt (à la attempts.ts)

src/creator/       authoring app
  App.tsx          route shell (quizzes / edit / wheels / editWheel / branding / settings)
  storage/db.ts    IndexedDB CRUD (quizzes, wheels, brandings, meta/settings) — DB v2
  storage/bundle.ts / wheelBundle.ts   export/import .quizzer.json / .wheelzer.json
  screens/         QuizList/QuizEditor/QuestionEditor, WheelList/WheelEditor/WheelDeployDialog,
                   BrandingManager, GlobalSettings, DeployDialog
  components/      Wysiwyg (TipTap), ColorField (react-colorful), uploadAsset
  deploy/          injectPayload, buildZip (externalize + pack), download,
                   index (quiz orchestrator), wheel (wheel orchestrator)
  generated/playerTemplate.ts, wheelTemplate.ts   committed stubs (see gotcha above)

scripts/           embed-{player,wheel}.mjs, ensure-{player,wheel}.mjs,
                   restore-stubs.mjs, check-stubs.mjs
tests/             88 vitest suites (incl. version.test.ts — compare/isNewer/unseenNotes)
```

## Data model (essentials)

- `Quiz` → name, intro/instructions HTML, optional `introMedia`, optional
  `timeLimitSec`, `attempts`, `randomizeQuestions`, `passingPct`,
  `certificateEnabled`, `brandingId`, `questions[]`.
- `Question` discriminated union (`type`): `truefalse | mc | multi | fill | short`.
  Shared base: `promptHtml`, optional `image`, `weight`, `correctText`,
  `incorrectText`, `showCorrectAnswer`.
- `Branding` → 5 colors, optional `logo`, `font` (`builtin` | `custom` TTF).
- `Wheel` → name, `descriptionHtml`, optional `media`, `choices[]` (1–30, each
  `{text, weight}`; weight 0 = never lands), `spinsPermitted` (0 = unlimited),
  `soundDefaultOn`, `pdfResultCount` (1 = latest, 0 = all), `resultLabel` (reveal
  caption), `spinSeconds` (spin length), `brandingId`.
- Quiz deploy payload (`kind:'quiz'`): quiz with answer fields **blanked**; answers
  live only in an obfuscated `answerKey`, rejoined by question id via `resolveQuestions`.
  Wheel deploy payload (`kind:'wheel'`): the wheel verbatim — nothing hidden (choices
  are printed on the wheel face, so there is no secret and no obfuscation).

## Grading semantics (constants in `model.ts`, covered by tests)

- multi = **all-or-nothing**; fill = **proportional** per blank; short `manual` =
  **auto-credit** ("self-graded", no grader in a deployed quiz).
- `normalize()` = trim + collapse whitespace + lower-case (unless case-sensitive) —
  the one helper every grader shares.

## Distribution: hosting the creator (≠ the in-app "Deploy")

Two unrelated meanings of "deploy" live in this repo — don't conflate them:

1. **In-app "Deploy"** (everything above) — the creator emitting a finished
   *quiz/wheel* file for a respondent. Per-activity output, origin-independent.
2. **Hosting the creator itself** (this section, since v0.4.0) — publishing the
   single-file *creator* to GitHub Pages so the author keeps one bookmark.

Hosted at **<https://bronty13.github.io/quizzer/>** (public repo
`bronty13/quizzer`, Pages = `main` / root). The creator's authored data lives in
**IndexedDB, keyed to origin**, so a stable `https://` URL is what keeps quizzes/
wheels intact across updates — the same argument CalendarMaker makes for
`localStorage`. (Local `file://`/dev copies are a *different* origin and won't
share that data — author from the bookmark.)

- **`npm run deploy`** (`scripts/deploy-pages.sh`): asserts `APP_VERSION`
  (`src/shared/appMeta.ts`) == `package.json` version → full `npm run build` →
  **`npm run restore:stubs`** (so the build's regenerated blobs don't dirty the
  tree) → writes `version.json` → pushes `index.html` + `version.json` to the
  Pages repo. Override target with `PAGES_REPO=owner/name`.
- **In-app update UX:** `UpdateBanner.tsx` fetches `version.json` on load and
  shows "Update now" when newer; `WhatsNew.tsx` + `data/whatsNew.ts` show a
  once-per-version popup (last-seen in `localStorage` `quizzer.lastSeenVersion`).
  Version math: `src/shared/version.ts` (numeric compare) + `appMeta.ts`.
- **Release checklist** lives in `docs/distribution.md`: bump both versions, add a
  `WHATS_NEW` top entry, update CHANGELOG/docs, `npm run typecheck && npm test`,
  `npm run deploy`.

## Commands

`npm run dev` (creator, ensures both templates) · `npm run dev:player` /
`npm run dev:wheel` (a player standalone + demo) · `npm run build` (the only correct
full build) · `npm test` (88) · `npm run typecheck` · `npm run restore:stubs` /
`npm run check:stubs` (before committing) · `npm run deploy` (publish creator to Pages).

## Extending — where things go

- **New question type:** add to the `Question` union + `QuestionType` (`model.ts`),
  a grader case (`grading.ts`), answer-key strip/restore (`payload.ts`), an editor
  sub-form (`QuestionEditor.tsx`), a player input (`QuestionView.tsx`), and tests.
- **New activity type (like the wheel):** add the entity + bundle to `model.ts`, a
  factory + demo (`factory.ts`), a payload (`*Payload.ts`), a DB store + CRUD
  (`db.ts`, bump `DB_VERSION`), bundle import/export, creator screens + a nav route
  (`App.tsx`), a deploy orchestrator (`deploy/*.ts`) reusing `injectScript`/`packZip`,
  and a **second player bundle** (`src/<x>-player/` + `vite.<x>.config.ts` +
  `embed-<x>.mjs` + `ensure-<x>.mjs` + a committed stub wired into `restore-stubs.mjs`
  / `check-stubs.mjs` + the `build` chain). Keep `build:creator` last.
- **New branded surface:** drive it from `brandingCss()` so creator + player match.
- **New deployable asset:** thread it through the `createExternalizer` helper in
  `buildZip.ts` so the zip format externalizes large copies.

## Known limitations

- Built-in fonts use system-font stacks (offline, zero-weight); upload a TTF for
  pixel-identical branding.
- Answer obfuscation is deterrence only — client-side grading can't keep answers
  secret. Not for high-stakes exams.
- Certificate uses jsPDF built-in fonts (not the branding font).

## PhantomLives note

Pure browser SPA — the macOS-app rules (`build-app.sh`/`install.sh`,
auto-backup-on-launch, `NavigationSplitView`, SQL-migration immutability) do **not**
apply. Release hygiene (version, CHANGELOG, README/USER_MANUAL, tests) does.
