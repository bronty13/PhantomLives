# Changelog

All notable changes to **Quizzer** are recorded here. This project follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and Semantic Versioning.

## 0.3.0 — 2026-06-06

### Added

- **Spin the Wheel** — a brand-new, standalone activity type alongside quizzes (a
  separate **Wheels** section in the creator's top nav). It is *not* a graded quiz:
  no questions, no pass/fail, no answer key. The creator configures a title, a
  description (rich text, default "Spin the Wheel for a Prize."), an optional
  image/video, **1–30 labeled choices**, a spins-permitted limit (`0` = unlimited),
  sound-on default, and how many results the PDF lists. Reuses the existing branding
  profiles (logo / colors / font) so the wheel matches your quizzes.
  - **Deployed wheel SPA** (a *second* self-contained player bundle, built through the
    same two-bundle pipeline): a branded, animated **canvas spin wheel** with the
    choices on its sectors, synthesized **Web Audio** tick + win-chime sound (a player
    toggle, default on, `prefers-reduced-motion` aware), an enforced spins limit
    (localStorage, like quiz attempts), a big animated **result reveal**, and a
    **"Download Result (PDF)"** that memorializes the win(s). Single-HTML and zip
    formats, offline under `file://`, on desktop and mobile.
  - **Optional weighting** (an "Advanced odds" toggle in the editor): each choice has a
    relative `weight` (default 1 = a fair wheel; `0` = never lands). Sectors always
    render equal-sized — only the landing probability changes.
  - **Global settings**: defaults for wheel description, spins permitted, sound-on, and
    PDF result count. Existing data is untouched (IndexedDB upgraded v1 → v2, additive
    `wheels` store; settings gain defaults transparently).
- **Build/tooling**: `build:wheel` / `embed:wheel` / `dev:wheel` scripts; the full
  `build` now runs `build:player → embed:player → build:wheel → embed:wheel →
  build:creator` (creator still last). `wheelTemplate.ts` joins `playerTemplate.ts` as
  a committed stub — `npm run restore:stubs` resets **both** and `npm run check:stubs`
  guards against committing a built blob.
- **Tests**: 77 vitest tests (was 44) — added spin math (weighted picker, angle
  round-trip, sector crossings), wheel payload, wheel deploy + asset externalization,
  wheel bundle round-trip, result-PDF generation, and a real-wheel-template integration
  check.

## 0.2.0 — 2026-06-05

### Added

- **Optional per-question image**, displayed between the question text and the
  answer choices. Upload it in the question editor; it renders in the deployed quiz
  and is externalized to `assets/` (like other large media) in the zip deploy format.
  Backward-compatible — the field is optional, so older bundles still import.

## 0.1.0 — 2026-06-05

Initial release. A portable quiz creator that deploys self-contained, offline,
branded quizzes to any browser.

### Added

- **Creator SPA** (Vite + React + TypeScript, single-file build): quiz management
  (create / edit / duplicate / delete / import / export / deploy), a quiz editor,
  per-type question editors, a branding manager, and global settings. Persists to
  the browser's IndexedDB.
- **Branding profiles**: five customizable colors (with a popover color picker), a
  logo upload, and a font — choose one of 10 built-in font stacks or upload a TTF
  (embedded as base64 `@font-face`). Applied to the creator and every deployed page.
- **Question types**: True/False, Multiple Choice (2–10, randomizable), Multiple
  Answer (2–10, randomizable, all-or-nothing), Fill-in-the-Blank (1+ blanks, 1+
  accepted answers each, proportional credit), and Short Answer (keyword or manual).
  Each question has a weight, custom correct/incorrect feedback, and a
  reveal-correct-answer toggle.
- **WYSIWYG** intro / instructions / question text via TipTap, sanitized with
  DOMPurify on store and render.
- **Deploy pipeline** (two-bundle architecture): a self-contained **player** bundle
  is built first and embedded into the creator as a string template; at deploy time
  the creator injects the quiz + branding and downloads either a **single
  self-contained `.html`** or a **`.zip`** (HTML + `assets/`) — chosen per deploy,
  with large intro videos steered to zip. The player reads `window.__QUIZ__` and
  never fetches, so it runs under `file://`, offline, on desktop and mobile.
- **Deployed quiz flow**: branded intro (name + WYSIWYG + optional image/video +
  optional time text), optional countdown timer, attempts limit, optional randomized
  question/answer order, per-question feedback, final PASS/FAIL summary, and a
  class-style **PDF completion certificate** (jsPDF) on a passing score.
- **Answer-key obfuscation** (base64 + XOR) — documented as deterrence, not security.
- **Tests**: 44 vitest tests across grading (all types), obfuscation round-trip,
  payload strip/restore, deploy injection + zip assembly, bundle import/export,
  certificate generation, HTML sanitization, and a real-template integration check.

### Notes

- Built-in fonts use cross-platform system-font stacks (offline, zero-weight) rather
  than shipping ~10 embedded webfaces in every quiz; upload a TTF for pixel-identical
  branding. Tracked for a future release.
- The macOS-app conventions (`build-app.sh`, `install.sh`, auto-backup-on-launch,
  `NavigationSplitView`, SQL-migration immutability) do not apply to this pure
  browser SPA.
