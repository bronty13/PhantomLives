# Changelog

All notable changes to the R-SICCI SPA are documented here.

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
