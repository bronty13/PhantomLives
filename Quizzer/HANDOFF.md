# Quizzer — Architecture Handoff

The canonical architecture snapshot. Read this before non-trivial changes. For the
*why* behind the decisions, see `DESIGN.md`; for usage, `README.md` / `USER_MANUAL.md`.

## What it is

Two products from one codebase:

- **Creator** (`src/creator/`) — a browser SPA you run to author quizzes. No server;
  data lives in the browser's IndexedDB. Built to `dist/index.html` (single file).
- **Player** (`src/player/`) — the deployed quiz a respondent opens. Self-contained,
  client-side-graded, runs offline / under `file://`. Built to
  `dist-player/index.html` (single file).

Both are bundled to a single self-contained HTML by `vite-plugin-singlefile`
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

Build order is load-bearing and enforced by the single `npm run build` script:
`build:player → embed:player → build:creator`. **Never run `build:creator` alone.**

At deploy time the creator replaces the `<!--QUIZ_PAYLOAD-->` marker in the template:

- **Single `.html`** — inline `<script>window.__QUIZ__=…</script>` (assets as base64
  data-URIs), injected *before* the player's module script.
- **`.zip`** — marker becomes `<script src="./data.js"></script>` (classic script,
  works under `file://`); `data.js` sets `window.__QUIZ__`; large assets are written
  to `assets/` and referenced by relative path.

The player is **format-agnostic**: it always reads `window.__QUIZ__` and resolves
each `AssetRef` (`{kind:'inline',dataUri}` or `{kind:'file',path}`) to an element
`src`. Never `fetch`.

### ⚠️ The committed-stub gotcha

`src/creator/generated/playerTemplate.ts` is a **committed ~471-byte stub** (valid
HTML with the marker, so `vite dev`/`tsc` resolve on a fresh checkout). `npm run
build` overwrites it locally with the real ~906 KB build. **Restore the stub before
committing** — never commit the built blob. `scripts/ensure-player.mjs` rebuilds it
for `npm run dev` when stale.

## File map

```
src/shared/        single source of truth, imported by BOTH apps
  model.ts         Quiz / Branding / GlobalSettings / Question union / AssetRef
  grading.ts       pure graders per type + normalize() + gradeQuiz()
  obfuscate.ts     base64+XOR answer-key scramble (deterrence, not security)
  payload.ts       buildPayload (strip+obfuscate answers) / resolveQuestions (player)
  branding.ts      Branding → CSS vars + @font-face
  fonts.ts         10 built-in font stacks + custom-TTF @font-face
  certificate.ts   jsPDF completion certificate
  sanitize.ts      DOMPurify wrapper for WYSIWYG HTML
  assets.ts        resolveAsset / size + inline-threshold
  dataurl.ts       data-URI ⇄ bytes + jsonForScript (JSON-in-HTML escaping)
  factory.ts       new entity factories + demoBundle()
  util.ts          shuffle / formatDuration / parseDuration / slugify

src/player/        deployed quiz
  bootstrap.ts     read window.__QUIZ__ (dev fallback = demoBundle) → resolve questions
  App.tsx          phase machine: intro → quiz → summary; attempts; timer
  flow/            IntroScreen, Timer, QuestionView, SummaryScreen, BrandBar, RichText
  attempts.ts      per-quiz attempt count (localStorage + in-memory fallback)

src/creator/       authoring app
  App.tsx          route shell (home / edit / branding / settings) + data load
  storage/db.ts    IndexedDB CRUD (quizzes, brandings, meta/settings)
  storage/bundle.ts  export/import .quizzer.json
  screens/         QuizList, QuizEditor, QuestionEditor, BrandingManager, GlobalSettings, DeployDialog
  components/      Wysiwyg (TipTap), ColorField (react-colorful), uploadAsset
  deploy/          injectPayload, buildZip (externalize + pack), download, index (orchestrator)
  generated/playerTemplate.ts   committed stub (see gotcha above)

scripts/           embed-player.mjs, ensure-player.mjs
tests/             45 vitest suites
```

## Data model (essentials)

- `Quiz` → name, intro/instructions HTML, optional `introMedia`, optional
  `timeLimitSec`, `attempts`, `randomizeQuestions`, `passingPct`,
  `certificateEnabled`, `brandingId`, `questions[]`.
- `Question` discriminated union (`type`): `truefalse | mc | multi | fill | short`.
  Shared base: `promptHtml`, optional `image`, `weight`, `correctText`,
  `incorrectText`, `showCorrectAnswer`.
- `Branding` → 5 colors, optional `logo`, `font` (`builtin` | `custom` TTF).
- Deploy payload: quiz with answer fields **blanked**; answers live only in an
  obfuscated `answerKey`, rejoined by question id via `resolveQuestions`.

## Grading semantics (constants in `model.ts`, covered by tests)

- multi = **all-or-nothing**; fill = **proportional** per blank; short `manual` =
  **auto-credit** ("self-graded", no grader in a deployed quiz).
- `normalize()` = trim + collapse whitespace + lower-case (unless case-sensitive) —
  the one helper every grader shares.

## Commands

`npm run dev` (creator, ensures player template) · `npm run dev:player` (player + demo)
· `npm run build` (the only correct full build) · `npm test` (45) · `npm run typecheck`.

## Extending — where things go

- **New question type:** add to the `Question` union + `QuestionType` (`model.ts`),
  a grader case (`grading.ts`), answer-key strip/restore (`payload.ts`), an editor
  sub-form (`QuestionEditor.tsx`), a player input (`QuestionView.tsx`), and tests.
- **New branded surface:** drive it from `brandingCss()` so creator + player match.
- **New deployable asset:** thread it through `externalizeAssets()` (`buildZip.ts`)
  so the zip format externalizes large copies.

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
