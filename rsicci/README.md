# R-SICCI — survey administration + scoring SPA

A single, self-contained HTML application that **administers** the *Research
Sexual Interests, Consent, and Context Inventory (R-SICCI, Draft v0.1)* and
**scores** the results — fully offline, no server, no network calls.

It is a non-clinical, **research-only**, IRB-gated instrument. It does **not**
diagnose, predict criminality, or determine fitness, eligibility, or treatment.

## Hosted

Live (single bookmarkable URL, updates on refresh):
**https://bronty13.github.io/rsicci/**

Participants and researchers can open that link in any modern browser — there's
nothing to install. The page is a fully client-side single file: **no participant
answers are ever transmitted** (they're exported to a local file). The hosted copy
and a saved `file://` copy behave identically.

Privacy caveats vs. the instrument's data-governance rules: the survey **content**
is publicly visible at the URL, and GitHub Pages logs visitor **IP addresses**
server-side. No answers are collected either way.

Deploy (source stays in this monorepo; only the built artifact is pushed to the
public `bronty13/rsicci` Pages repo):

```sh
npm run deploy            # build → push dist/index.html + version.json → Pages
PAGES_REPO=me/rsicci npm run deploy
```

## Two roles, one file

The built file (`dist/index.html`) has a home screen with two modes:

| Mode | Who | What it does |
|---|---|---|
| **Take the survey** | a participant | Runs the 11-module questionnaire and exports **one data file** at the end. |
| **Score a data file** | the researcher | Imports a returned data file and produces the descriptive research profile. |

Distribute the *same* file to participants; collect their data files; open the
file yourself in **Score** mode. There is nothing to install and no account.

## The data file

At the end of the survey the participant saves a single file containing only a
generated **study ID**, the instrument version, the method condition, their
answers (with display-state and timing), and QA fields — **no name, email, or
contact details** (per the instrument's data-separation rule).

- **Encrypted (`.rsicci`, default)** — AES-GCM with a key derived from a
  passphrase (PBKDF2, SHA-256, 210k iterations). The researcher enters the same
  passphrase to score it. Share the passphrase through a **separate channel**
  from the file; if lost, the file cannot be opened.
- **Plain (`.json`)** — readable, for testing and transparency.

## Scoring

The pure, DOM-free engine (`src/score/engine.ts`) implements the 10 published
score rules and 9 classification axes, faithfully honoring the instrument's
correctness rules:

- **97/98/99 are MISSING, not zero** — excluded from every mean and the valid
  count, but still counted in the *displayed* denominator for eligibility gates.
- **Per-score eligibility gates** return *"not computed"* (never a partial
  number) when unmet (e.g. ≥70% of displayed Appeal/Desire cells for CII/CIB,
  ≥9 of 12 for CCS).
- **Reverse coding follows the published score rules, not the item-bank flag.**
  Only `CON_PRESSURE` (CCS) and `WB_STRESS` (EWI) are reversed inside composites.
  The SDS rule sums the SOC worry items **raw** (higher worry = higher strain),
  even though those items carry an intrinsic `reverse_coded` flag in the bank.
- **SRI is computed as an individual, researcher-facing index** (overall 0–100,
  thought-frequency and severity sub-scores, a per-theme breakdown, and the
  prevalence of non-zero thought-frequency across the 8 sensitive themes). It
  stays **restricted**: researcher-access only, never participant-facing, and
  explicitly **not** a risk, dangerousness, or likelihood-of-offending measure.
  It is computed only when the participant opted into Module J. (This relaxes the
  draft instrument's aggregate-only stance at the maintainer's direction; the
  misuse guardrails from `prohibited_uses` are kept intact.)

The xlsx specification's "Scoring Example" (CII = 50, CIB = 2, CAP = 40, max
practice = 4) is used verbatim as a unit-test fixture.

Alongside the CII/CIB/CAP aggregates, the report shows a **per-theme breakdown**
of the 38 Module-D interest themes (raw Appeal/Desire/Practice, theme interest
mean/%, and a breadth marker for themes ≥ 2.0) — the non-restricted counterpart
of the SRI per-theme table.

### Scoring interpretations chosen where the draft is ambiguous

The draft instrument leaves two points open; these were resolved by judgment and
are called out so a researcher reconciling against a preregistration can see them:

- **SDS and DFI combine two sub-means, not a pooled mean.** The rules read
  "*mean of [core items], plus the mean of [selected-theme items]*". This SPA
  computes `(coreMean + addonMean) / 2` (when the selected-theme add-on is
  present), not a single mean over the pooled item set. The two differ when the
  core and add-on counts differ.
- **DFI band cutoffs (33 / 66) are this SPA's, not the instrument's.** The DFI
  rule names three tags (Limited / Some / Substantial self-reported impact) with
  **no numeric anchors**, so the 0–33 / 34–66 / 67–100 bands are a local choice.
  CII / KIS / CCS bands, by contrast, come from the instrument's own anchors.
- **SRI is defined and banded locally.** The draft instrument specifies SRI as
  aggregate-only and gives it no individual formula or anchors. The individual
  index here is `mean of all valid Module-J cells / 4 × 100`, with sub-scores for
  thought-frequency and severity (unwantedness + impact) and Minimal/Low/Moderate/
  High (0–24/25–49/50–74/75–100) descriptive bands — all a local design choice.

## Develop / build / test

```sh
npm install
npm run dev        # local dev server
npm test           # vitest — engine, datafile, integration (29 tests)
npm run typecheck  # tsc --noEmit
npm run build      # → dist/index.html (single self-contained file)
```

`npm run build` inlines all JS/CSS and the embedded instrument JSON into one
`dist/index.html` via `vite-plugin-singlefile`. That file is the distributable.

### Verification status

Automated coverage (33 vitest tests) proves the scoring engine, the datafile
crypto round-trip, and that every screen — including the full Module-D matrix,
Module-E follow-ups, and the export panel — renders without crashing. **One
manual pass is still recommended and currently unverified** (the browser
automation extension was unavailable): open the built `dist/index.html` directly
via `file://` and run one end-to-end round-trip — take the survey, fill some of
the D matrix, select a theme and confirm its E follow-ups appear, export
encrypted, reopen in **Score** mode, decrypt, and read the report. If a browser
ever reports that password protection is unavailable on `file://`, the export
panel automatically falls back to the plain file and explains why; serving the
file over `http(s)://` restores encryption.

## Scope notes (v0.1)

- Only the **structural** skip rules are modelled (eligibility termination, the
  Module-E selected-theme indirection, the Module-J opt-in). Other conditional
  items are shown and may be skipped — over-showing is safe because every
  sensitive item allows skip / prefer-not-to-answer and nothing forces a
  response.
- Method-condition randomization records a condition but does not yet vary the
  displayed wording (only one wording set is authored).
- Not multi-instrument: built specifically for R-SICCI Draft v0.1 (the
  instrument JSON is swappable, but the engine encodes this instrument's rules).

## Prohibited uses

No clinical diagnosis or paraphilic-disorder classification; no risk /
likelihood-of-offending / hiring / academic / relationship-compatibility /
insurance score; no automatic staff alerts (support resources are
participant-controlled and IRB-approved); no merging of restricted Module-J/SRI
variables into any participant-facing profile.
