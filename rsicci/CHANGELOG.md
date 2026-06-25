# Changelog

All notable changes to the R-SICCI SPA are documented here.

## Unreleased

- **Hosted on GitHub Pages** at https://bronty13.github.io/rsicci/ so external
  participants/researchers can run it from a link (the NFEditor/CalendarMaker
  pattern). Adds `scripts/deploy-pages.sh` + `npm run deploy` (builds, then pushes
  the single-file artifact + `version.json` to the public `bronty13/rsicci` Pages
  repo) and `base: './'` in the Vite config so the one inlined `index.html` runs
  identically from the Pages URL and a saved `file://` copy. No app-behavior change
  (app version stays 0.3.0); the deploy is fully client-side — no answers are
  transmitted.

## 0.3.0 — 2026-06-24

- **Per-theme breakdown for the non-restricted Module D interest themes**
  (parallels the SRI per-theme table). The scoring engine now retains, for each
  of the 38 themes, the raw Appeal/Desire/Practice values, the theme interest
  mean and %, the Practice %, and `endorsed` / `meetsBreadth` flags. The report
  renders an "Interest themes — per-theme breakdown" table (engaged themes only,
  sorted by interest, with the breadth-contributing themes highlighted).
- New tests assert the breakdown's raw cells, derived fields, null handling, and
  that the breadth-flagged count matches CIB; 39 tests total.

## 0.2.0 — 2026-06-24

- **SRI is now scored as an individual, researcher-facing index** (at the
  maintainer's direction, relaxing the draft instrument's aggregate-only stance).
  Adds an overall 0–100 index, thought-frequency and severity (unwantedness +
  impact) sub-scores, a per-theme breakdown across the 8 sensitive themes, and
  the prevalence of non-zero thought-frequency. Computed only when the participant
  opted into Module J. The misuse guardrails are kept intact: SRI stays
  restricted/researcher-only, never participant-facing, and is explicitly **not**
  a risk, dangerousness, or likelihood-of-offending measure. The classification's
  9th axis now presents SRI instead of withholding it.
- New tests for SRI (opt-in gating, overall/sub-score/prevalence math, axis
  presentation) and the populated SRI report render; 35 tests total. README +
  CHANGELOG document SRI as a locally-defined, locally-banded index.

## 0.1.0 — 2026-06-24

Initial release.

- **Dual-mode single-file SPA** (Vite + React + TypeScript, built to one
  self-contained `dist/index.html` via `vite-plugin-singlefile`). Home screen
  offers *Take the survey* (administration) and *Score a data file* (researcher).
- **Administration**: all 11 modules (A–K) of R-SICCI Draft v0.1; Module D
  rendered as the 38-theme × Appeal/Desire/Practice matrix; Module E
  selected-theme follow-ups gated to endorsed themes; Module J behind its opt-in;
  eligibility termination; the optional DFI safety/function support-resources
  screen; localStorage pause/resume; per-item display-state and timing capture.
  The participant copy ends on a neutral completion screen (never their scores).
- **Data file**: encrypted `.rsicci` (AES-GCM + PBKDF2, default) or plain `.json`
  (toggle). Contains a generated study ID, instrument version, method condition,
  answers + display-state, and QA — no direct identifiers.
- **Scoring engine** (pure, DOM-free): the 10 score rules (CII, CIB, CAP, KIS,
  CCS, CEI, SDS, DFI, EWI; SRI withheld) and 9 classification axes, honoring
  97/98/99-as-missing, per-score eligibility gates, score-rule-driven reverse
  coding, and the SRI/Module-J no-individual-scoring constraint.
- **Tests**: 29 vitest cases — engine (incl. the xlsx worked-example fixture
  CII=50/CIB=2/CAP=40, missing-code handling, reverse-coding-per-rule including
  the raw-SDS check, eligibility gates, SINGLE-input coding maps), datafile
  (encrypt/decrypt round-trip, wrong-password failure, fresh salt/iv, format
  auto-detect), and an integration test (full score→encrypt→reload→decrypt→
  re-score path + headless render of `App` and `Report`).
