---
title: Data privacy & governance
module: 12 — Governance, Safety & Compliance
lesson: 02
est_time: 40 min reading
last_reviewed: 2026-06-26
tags: [ai, governance, privacy, gdpr, training-data, provenance]
---

# Data privacy & governance

AI runs on data, and most of that data is *about people* — which puts AI
squarely inside privacy law. This lesson covers the durable privacy principles
that govern AI, the specific tension between how LLMs work and how privacy law is
written, and the training-data provenance discipline that ties it together. The
durable principles here long predate AI; what's new is how awkwardly LLMs fit
them.

> ⚠️ **Dated snapshot — June 2026.** Enforcement actions and regulator opinions
> evolve; the *principles* are durable, the *cases* are perishable.

---

## The durable privacy principles

Whether you're under GDPR (EU/UK), CCPA/CPRA (California), or one of the many
laws modeled on them, the same core principles recur. Anchor your AI governance
on these — they don't move:

- **Lawful basis.** Every distinct processing operation needs a legal
  justification. "We're building AI" is **not** a basis. Under GDPR the realistic
  options for training are *consent* (rarely feasible at web scale) or *legitimate
  interest* (the workhorse — but it must pass a balancing test).
- **Purpose limitation.** Collecting data, pre-processing it, *training* on it,
  and *deploying* the model are **separate purposes**, each needing its own
  justification. You can't collect for one stated purpose and silently train on
  it.
- **Data minimization.** Use only what's adequate, relevant, and necessary — the
  hardest prong to satisfy for "train on everything" approaches, and the one
  regulators press on.
- **Transparency, accuracy, storage limitation, accountability.** Tell people
  what you do with their data; keep it accurate; don't retain it indefinitely;
  and be able to **demonstrate** compliance, not just assert it.
- **Special-category data** (health, biometrics, race, etc.) gets stricter
  protection — the default regulator expectation is to *filter it out at
  collection or delete it before training.*

---

## The hard part: LLMs don't fit the law's assumptions

Privacy law was written for *databases* — discrete records you can look up,
correct, and delete. An LLM stores information very differently, and that mismatch
creates two genuinely unresolved tensions every AI builder should understand.

### Is a trained model "anonymous"?

If model weights were truly anonymous (no personal data inside), privacy law
wouldn't apply to them. But the authoritative EU position (the EDPB's 2024
opinion) is that **a model is not automatically anonymous** — it's a case-by-case
determination, and crucially, **a model that memorizes and can regurgitate its
training data is *not* anonymous**, so full privacy law applies to the weights
themselves. The practical consequence: "our model is anonymous" is a **claim you
must evidence** (with extraction and membership-inference testing — the
[Module 5 eval](../part-05-evaluation/00-the-eval-mindset.md) and
[Module 6 data](../part-06-fine-tuning/02-data.md) discipline applied to
privacy), not a default you get to assume. And the same model can be judged
differently by different national regulators — an under-determined area to watch.

### The right to erasure vs. trained weights

GDPR's **right to be forgotten** (and right of access) assumes retrievable
records. In an LLM, a person's data is *diffused across billions of weights* —
there's no row to delete. Full retraining to remove one individual is
economically prohibitive. The proposed technical fix, **"machine unlearning," is
immature** — current methods don't fully forget (the information still leaks via
crafted prompts). The durable, honest framing: **treat machine unlearning as
risk-reduction, not compliance-grade deletion.** And note the bite: if your model
*can* regurgitate (so it isn't anonymous), the weights are personal data and the
erasure duty genuinely attaches — a hard, partly-unsolved problem you should
design *around* (filter at training time) rather than promise to solve after the
fact.

---

## Training-data provenance

The cleanest way to stay on the right side of all of the above is to **know where
your training data came from** — provenance discipline, which is both a privacy
practice and (per [Module 6](../part-06-fine-tuning/02-data.md)) a quality one:

- **Record the source and basis for each dataset** — scraped, purchased,
  licensed, user-provided, synthetic — and the lawful basis you're relying on for
  it. This record is also what regulators increasingly *require* you to publish:
  California's training-data-transparency law (in force) mandates a public
  summary of your training datasets, including whether they contain PII or
  copyrighted material; the EU AI Act requires GPAI providers to publish a
  summary of training content.
- **Web-scraped data is the sharp edge.** It's the default training source and
  the hardest to justify — the UK regulator's position is that *legitimate
  interest is the only viable lawful basis for web-scraped training data*, and
  only if it passes the three-part test. Scraping facial images for biometric
  systems has drawn some of the largest fines on record.
- **The copyright dimension.** Beyond privacy, training data raises unsettled
  copyright questions (covered as a licensing axis in
  [Module 9, lesson 03](../part-09-multimodal/03-image-and-video-generation.md)
  for generated *output*; here it's about the *input*). Provenance records are
  your evidence either way.

---

## US privacy hooks

The US has no single federal privacy law, but **CCPA/CPRA** (California) gives a
broad definition of personal information, consumer rights to access/delete/correct
and opt out of sale/sharing, codified data-minimization and purpose-limitation,
and **required disclosed retention periods** (no indefinite retention) — all
directly relevant to how you govern a training corpus. New regulations there
phase in automated-decision-making rights (notice, opt-out, risk assessments) over
the next couple of years. The pattern echoes GDPR's principles, which is exactly
why anchoring on the durable principles above travels across jurisdictions.

`★ Insight ─────────────────────────────────────`
- **The durable privacy principles (lawful basis, purpose limitation,
  minimization) travel across jurisdictions** — anchor your AI data governance on
  them and the specific laws become instances, not surprises.
- **LLMs break two of privacy law's core assumptions** — a memorizing model may
  not be "anonymous," and erasure has no clean technical answer (unlearning is
  risk-reduction, not deletion). The defensible response is provenance discipline
  and filtering *at training time*, not promising after-the-fact fixes the
  technology can't deliver.
`─────────────────────────────────────────────────`

## Next

→ [Documentation & accountability](03-documentation-and-accountability.md) — the
artifacts that prove you govern responsibly.
