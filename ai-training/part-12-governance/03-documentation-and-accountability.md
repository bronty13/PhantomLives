---
title: Documentation & accountability
module: 12 — Governance, Safety & Compliance
lesson: 03
est_time: 35 min reading
last_reviewed: 2026-06-26
tags: [ai, governance, documentation, model-cards, accountability, audit]
---

# Documentation & accountability

Governance that isn't written down isn't governance — it's good intentions. This
lesson covers the **documentation artifacts** that record what an AI system is,
how it was built, and how it behaves, plus the **inventories and audit trails**
that make an organization accountable for its AI. The artifacts are durable
(they've been standard practice for years); the legal requirements that mandate
them are the dated part.

---

## The documentation taxonomy: datasheet → model card → system card

Three artifacts, each documenting a different layer, that compose into a full
accountability record:

| Artifact | Documents | Key contents |
|---|---|---|
| **Datasheet for a dataset** | the *data* | motivation, composition, collection process, preprocessing/labeling, recommended uses, maintenance |
| **Model card** | a *trained model* | intended and out-of-scope use, **performance disaggregated across groups**, training/eval data, ethical considerations, caveats |
| **System card** | a *deployed system* | capabilities, **safety evaluations** (red-teaming, dangerous-capability evals), risk analysis, mitigations, deployment decisions |

The distinction is worth memorizing: **datasheet = data, model card = model,
system card = the deployed system plus its safety story.** They nest — a system
card references the model cards of its models, which reference the datasheets of
their training data.

The two ideas that make these powerful:

- **Disaggregated performance** (the model card's signature contribution).
  Reporting one aggregate accuracy number hides discrimination — a model can be
  95% accurate overall and far worse for a subgroup. A model card forces you to
  report performance *broken down across groups*, which surfaces the fairness
  problems an aggregate would bury. This is the [Module 5 grading
  discipline](../part-05-evaluation/02-grading-methods.md) with an
  accountability purpose.
- **Out-of-scope use.** Stating plainly what a model *should not* be used for is
  both an honesty practice and a liability boundary — it's the documentation
  twin of [Module 11's expectation-setting](../part-11-product-ux/05-onboarding-and-the-feedback-flywheel.md).

> ⚠️ **A public model card does *not* by itself satisfy a regulator.** It's a
> great practice and a great start, but the EU AI Act's high-risk documentation
> demands much more (risk management, conformity assessment, lifecycle change
> logs). Don't mistake a published card for compliance.

---

## What the law requires (the dated part)

For high-risk systems, the EU AI Act turns documentation from best practice into
a binding obligation:

- **Technical documentation** (Article 11 + Annex IV) — drawn up *before* the
  system goes to market and kept current: system description and intended
  purpose, development process and design choices, **the data** (datasets,
  provenance, labeling, cleaning), training/testing methods and metrics, the
  risk-management measures, human-oversight design, accuracy/robustness/
  cybersecurity, and a declaration of conformity. This is the regulator-grade
  superset of a datasheet + model card.
- **Automatic logging** (Article 12) — high-risk systems must automatically
  record events over their lifetime for traceability and post-market monitoring.
  An *engineering* requirement: your system has to emit an audit log by design.
- **GPAI documentation** — general-purpose model providers keep technical
  documentation, pass transparency information to downstream developers, and
  publish a summary of training content.
- **Public registration** — high-risk providers must register the system in an
  EU public database before deployment, a regulatory-level inventory obligation.

These dates and exact contents are perishable (and the timeline shifted — see
[lesson 01](01-the-regulatory-landscape.md)); the *durable* lesson is that
**documentation is the evidence layer of governance**, and for high-risk uses
it's mandatory and auditable.

---

## AI inventories: the system of record

You cannot govern what you don't know you have. The backbone of an
organizational AI program is an **AI inventory** — an internal register of every
AI system, each entry recording its owner, purpose, **risk tier**
([lesson 00](00-why-governance.md)), data sources, lawful basis, and links to its
model card / datasheet / impact assessment.

The inventory is what makes the rest operable: it maps each system to its
documentation and its obligations, so when a regulation changes or an incident
occurs you can answer "which of our systems does this affect?" in minutes, not
weeks. (The EU's public high-risk database and California's risk-assessment
filings are external, regulator-facing versions of the same idea.) For a small
team this can be a spreadsheet; the point is that it *exists and is maintained* —
a shadow AI system nobody catalogued is a governance gap by definition.

---

## Audit trails and transparency reports

Two more accountability layers:

- **Audit trails / logging.** Beyond the EU's legal mandate, comprehensive
  logging of inputs, outputs, decisions, and human interventions is a core
  practice under both NIST's RMF and ISO 42001. It's also what makes
  [Module 7 cost attribution](../part-07-cost-and-latency/05-production-economics-and-build-vs-buy.md),
  [Module 5 production eval](../part-05-evaluation/05-evaluation-in-production.md),
  and [incident response](05-operationalizing-governance.md) possible — the same
  log serves governance, ops, and debugging.
- **Transparency reports.** Voluntary public disclosures about model capabilities,
  limitations, and safety practices. Third parties even benchmark them (Stanford's
  Foundation Model Transparency Index), giving you an external yardstick for how
  complete your disclosure is.

`★ Insight ─────────────────────────────────────`
- **Datasheet / model card / system card is a nesting taxonomy** — data, model,
  deployed system + safety — and the model card's *disaggregated* performance is
  the part that turns documentation into a fairness control, surfacing what an
  aggregate metric hides.
- **An AI inventory is the system of record that makes a program operable** — you
  can't govern, or answer a regulator about, AI systems you never catalogued. Pair
  it with audit logging (a legal must for high-risk) and a published model card is
  a start, never the finish line.
`─────────────────────────────────────────────────`

## Next

→ [Risk assessment & red-teaming](04-risk-assessment-and-red-teaming.md) — finding
the harms before they find you.
