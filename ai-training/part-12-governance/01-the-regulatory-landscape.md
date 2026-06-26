---
title: The regulatory landscape
module: 12 — Governance, Safety & Compliance
lesson: 01
est_time: 45 min reading
last_reviewed: 2026-06-26
tags: [ai, governance, regulation, eu-ai-act, nist, iso]
---

# The regulatory landscape

This is the most **perishable** lesson in the entire course — a map of laws and
standards that shift monthly. Read it for the *shape* of the landscape and the
durable frameworks underneath; treat every date and number as a snapshot to
re-verify. To prove the point, this lesson opens with a deadline that was
"settled" and then moved.

> ⚠️ **Dated snapshot — June 2026, and rotting fast.** Re-verify against the
> primary sources (the "how to re-verify" list at the end) before relying on any
> specific here. Status flags: **[IN FORCE]**, **[PENDING]**, **[DELAYED]**,
> **[REPEALED]**.

---

## The EU AI Act — the world's first horizontal AI law

**Regulation (EU) 2024/1689** is the most comprehensive AI law in force, and its
**risk-based tiering** ([lesson 00](00-why-governance.md)) is the durable model
much of the world is converging toward — unacceptable / high / limited / minimal,
with obligations scaled to the tier. That structure is stable. The *timeline* is
not.

### A live lesson in perishability

The Act phases in over years. As originally enacted:

- **[IN FORCE]** Aug 2024 — entry into force.
- **[IN FORCE]** Feb 2025 — prohibited practices (Art. 5) + AI-literacy duties.
- **[IN FORCE]** Aug 2025 — general-purpose AI (GPAI) obligations, governance,
  penalties.
- **Aug 2026 / Aug 2027** — the heavy high-risk obligations and Art. 50
  transparency.

But in mid-2026 the Commission's **"Digital Omnibus on AI"** simplification
package **[PENDING — Parliament-adopted June 2026, awaiting final Council
adoption + Official Journal publication]** *postponed* the key deadlines:

| Obligation | Original | New (Omnibus) |
|---|---|---|
| High-risk stand-alone (Annex III) | Aug 2026 | **Dec 2027** |
| High-risk embedded in regulated products (Annex I) | Aug 2027 | **Aug 2028** |
| Art. 50 AI-content labelling | Aug 2026 | **Nov 2026** |

**The teaching point is bigger than the dates.** The popular tracker sites still
showed the *old* dates after the delay was agreed — so a developer trusting a
convenient third-party timeline would have planned against a deadline that no
longer applied. **This is why the course's "re-verify against the primary source"
rule is not pedantry in governance — it's how you avoid building to a wrong
legal deadline.** (And note the conditionality: the high-risk delay is a
"stop-the-clock" tied to supporting standards being ready, not a flat calendar
move — itself subject to change.)

### What high-risk actually demands

For a high-risk system (hiring, credit, education, critical infrastructure, law
enforcement, medical-device components), the obligations are heavy and *land on
engineering*: a risk-management system, data governance, technical documentation
(see [lesson 03](03-documentation-and-accountability.md)), automatic logging,
**human oversight** (see [lesson 05](05-operationalizing-governance.md)),
accuracy/robustness/cybersecurity, conformity assessment, and registration in an
EU public database. Penalties run to **€35M / 7%** of global turnover for
prohibited practices, **€15M / 3%** for other breaches.

### GPAI and the Code of Practice

General-purpose model providers have their own obligations (since Aug 2025):
technical documentation, a copyright policy, a **public summary of training
content**, and — for "systemic-risk" models (very large training compute) —
adversarial evaluations and serious-incident reporting. The voluntary **GPAI Code
of Practice** is the main route to demonstrate compliance; most frontier labs
signed, with notable exceptions — a reminder that even "industry consensus" is
contested.

---

## The United States — a deregulatory federation with a state patchwork

The US picture is almost the inverse of the EU's, and it's volatile:

- **No comprehensive federal AI statute.** The federal executive posture as of
  mid-2026 is firmly **deregulatory** and actively hostile to state AI laws
  (a December 2025 executive order directs litigation and funding pressure
  against them) — though an executive order **cannot by itself override state
  law**, so the state rules remain enforceable pending court challenges. A 2025
  attempt to impose a federal *moratorium* on state AI laws **[DEAD]** (stripped
  by the Senate 99–1).
- **A softening state patchwork.** The flagship **Colorado AI Act** was
  **[REPEALED & REPLACED]** before it took effect, swapped for a thinner
  transparency law (effective 2027). **California** is now the substantive US
  leader: a frontier-AI safety/transparency statute **[IN FORCE]** (incident
  reporting, published safety frameworks) and a training-data-transparency law
  **[IN FORCE]** (public training-dataset summaries). Plus sectoral and
  state-specific rules — NYC's hiring-tool bias-audit law, Texas, Illinois.
- **Sectoral regulators** retain existing authority — the FTC (deceptive "AI
  washing" claims under its general powers), the FDA (AI medical devices),
  employment law (Title VII still applies to AI hiring tools even after
  AI-specific guidance was withdrawn).

The durable takeaway through all the churn: **in the US you govern against a
patchwork** — federal posture *plus* the specific states and sectors you operate
in — and that patchwork is in motion. Map your jurisdictions; don't assume one
national rule.

---

## The voluntary frameworks that anchor good practice

Independent of any law, two voluntary frameworks are the durable backbone of an
AI governance program — and they don't rot the way statutes do:

- **NIST AI Risk Management Framework (AI RMF 1.0)** — the US reference, built on
  four functions: **GOVERN** (culture, policy, accountability across all stages),
  **MAP** (frame the risks of a specific system in context), **MEASURE** (analyze
  and monitor risk), **MANAGE** (treat, respond, prioritize). Its companion
  **Generative AI Profile** layers on ~12 GenAI-specific risks — including
  confabulation (hallucination), data privacy, information security (prompt
  injection, poisoning), and IP. GOVERN-MAP-MEASURE-MANAGE is a clean,
  durable mental model for *any* AI risk program, law or no law. *(The RMF is
  under revision as of this snapshot — the functions are stable; cite the current
  version for specifics.)*
- **ISO/IEC 42001:2023** — the world's first **certifiable** AI management system
  standard. Where NIST gives you a framework, ISO 42001 gives you an auditable
  *management system* (Plan-Do-Check-Act, like ISO 27001 for security): a
  third-party certification you can show customers and regulators. Increasingly
  the procurement-grade proof that you govern AI responsibly. Companions:
  ISO/IEC 23894 (risk guidance), 42005 (impact assessment).

These two are where you *start* if you're building a program from scratch — they
encode the durable practices (lifecycle risk management, documentation, impact
assessment, monitoring) that the laws then make mandatory for high-risk uses.

---

## How to re-verify (this lesson rots — check on a cadence)

- **EU AI Act** (monthly — fastest-moving): the consolidated Regulation on
  EUR-Lex (the binding text); the European Commission AI Act pages; the European
  Parliament "Legislative Train" for the Digital Omnibus status. **Do not trust
  third-party timeline trackers for dates until they're updated post-Omnibus.**
- **US** (monthly federal, quarterly state): whitehouse.gov presidential actions,
  congress.gov, and the specific state legislature/AG sites for the states you
  operate in.
- **Standards** (semi-annually): nist.gov for the RMF revision; iso.org for the
  42001 family.

`★ Insight ─────────────────────────────────────`
- **The EU AI Act's risk tiering is the durable model; its timeline is a moving
  target** — the mid-2026 Omnibus delay (which the trackers lagged) is the
  course's "re-verify the primary source" rule shown in real consequences: plan
  to a stale deadline and you build the wrong thing.
- **Govern against a map, not a single rule.** EU horizontal law, a US
  deregulatory-federal-plus-state-patchwork, and the voluntary NIST/ISO
  frameworks coexist — start your program on the durable frameworks (GOVERN-MAP-
  MEASURE-MANAGE, ISO 42001) and layer the jurisdiction-specific law on top.
`─────────────────────────────────────────────────`

## Next

→ [Data privacy & governance](02-data-privacy-and-governance.md) — GDPR/CCPA
applied to AI, and the training-data tension.
