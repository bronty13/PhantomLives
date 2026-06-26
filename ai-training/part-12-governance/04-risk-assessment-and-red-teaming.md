---
title: Risk assessment & red-teaming
module: 12 — Governance, Safety & Compliance
lesson: 04
est_time: 40 min reading
last_reviewed: 2026-06-26
tags: [ai, governance, risk-assessment, red-teaming, safety, owasp]
---

# Risk assessment & red-teaming

Governance isn't only documenting what you built — it's *deliberately looking for
how it could go wrong* before it does. This lesson covers the two practices that
do that: **impact assessments** (structured analysis of potential harms before
deployment) and **red-teaming** (adversarial testing to find failure modes). It's
also where the security threads running through the whole course —
[Module 2](../part-02-prompt-engineering/04-reliability-security-and-evaluation.md),
[Module 3](../part-03-rag/05-evaluation-security-and-production.md),
[Module 4](../part-04-agents-and-tool-use/05-safety-security-and-reliability.md),
[Module 10](../part-10-coding-agents/05-security-and-failure-modes.md) — come
together under a governance frame.

---

## Impact assessments: harm analysis before deployment

The durable principle: **assess the potential for harm *before* you deploy, not
after an incident.** Several frameworks formalize this, and they overlap:

- **Fundamental Rights Impact Assessment (FRIA)** — the EU AI Act requires
  *deployers* of certain high-risk systems (public bodies, and anyone using
  high-risk AI for creditworthiness or insurance pricing) to complete one
  **before first use**: the processes involved, how often it's used, who's
  affected, the specific risks, and the human-oversight and mitigation measures.
- **Data Protection Impact Assessment (DPIA)** — GDPR mandates one whenever
  processing is "likely to result in high risk," which most consequential AI
  triggers (automated decisions, large-scale or sensitive data, systematic
  profiling). A FRIA and a DPIA overlap and can be **reused** — do the analysis
  once, satisfy both.
- **ISO/IEC 42005** — a standards-body methodology for structuring AI impact
  assessments across the lifecycle, covering intended *and* unintended
  consequences.

The common shape — and the durable part — is the same regardless of which form
you fill in: **enumerate who could be harmed and how, assess the likelihood and
severity, and document the mitigations.** That's risk-based thinking
([lesson 00](00-why-governance.md)) made into a concrete, repeatable artifact, and
it's the input that decides how much governance a system needs.

---

## Red-teaming as a governance practice

Where an impact assessment *reasons* about harms, **red-teaming goes and tries to
cause them.** NIST's durable definition: adversarial testing of an AI system under
stress to seek out failure modes and vulnerabilities — sitting inside the RMF's
MEASURE function, recommended **both before and after deployment.**

AI red-teaming is broader than classic security red-teaming, and the difference
is the durable insight:

- **Classic security red-teaming** targets the *infrastructure* — can I breach
  the server, escalate privileges, exfiltrate the database?
- **AI red-teaming additionally targets the *model's behavior*** — can I jailbreak
  it, inject a prompt, make it produce harmful/biased/false output, leak its
  training data or system prompt, or take an unsafe autonomous action? These
  failures are **probabilistic and emergent**, not a patchable bug, which is why
  red-teaming an AI system is a continuous practice, not a one-time pen test.

And it's **sociotechnical** — it tests harms to *people* (bias, manipulation,
misinformation), not just technical compromise. That's what makes it a
*governance* practice and not only a security one.

### The threat taxonomies

You don't have to brainstorm attack types from scratch — two living catalogs map
the territory:

- **OWASP Top 10 for LLM Applications** — the canonical risk list, with **prompt
  injection at #1**, followed by sensitive-information disclosure, supply-chain
  risks, data/model poisoning, improper output handling, **excessive agency**,
  system-prompt leakage, embedding weaknesses, misinformation, and unbounded
  consumption. This is the same list that underpins the security lessons in
  [Module 4](../part-04-agents-and-tool-use/05-safety-security-and-reliability.md)
  and [Module 10](../part-10-coding-agents/05-security-and-failure-modes.md) — here
  it's the *checklist* for what to red-team.
- **MITRE ATLAS** — an ATT&CK-aligned knowledge base of real adversary tactics
  and techniques against AI/ML systems (evasion, model stealing, poisoning,
  prompt injection), useful for structuring a thorough adversarial test.

The [Module 4 lethal trifecta](../part-04-agents-and-tool-use/05-safety-security-and-reliability.md)
and [Module 10's untrusted-content→config→execution pattern](../part-10-coding-agents/05-security-and-failure-modes.md)
are specific, high-value things to red-team for in any agentic system.

---

## Safety evaluations and frontier "if-then" frameworks

At the frontier, where models approach genuinely dangerous capabilities, two
governance practices have emerged that are worth understanding even if you're not
training frontier models:

- **Independent external evaluations.** Frontier developers increasingly
  commission *third-party* assessments — independent labs probing for autonomy,
  deception, or cyber-offense capability — as a confidence-building, confirmatory
  layer beyond internal testing. The
  [Module 5 lesson](../part-05-evaluation/03-llm-as-judge.md) that "you can't
  grade your own homework" applied at the safety level.
- **Capability-threshold ("if-then") frameworks.** The durable pattern: define
  dangerous-capability thresholds in advance, and *crossing one automatically
  triggers stricter safeguards.* Anthropic's Responsible Scaling Policy (with its
  AI Safety Levels), OpenAI's Preparedness Framework, and Google DeepMind's
  Frontier Safety Framework all share this shape — pre-commit to "**if** the model
  can do X, **then** we apply safeguards Y" so the safety response isn't
  improvised under commercial pressure. It's the safety-governance version of
  [Module 5's pre-registered eval gates](../part-05-evaluation/05-evaluation-in-production.md):
  decide the bar before you know the result. *(The specific levels, thresholds,
  and versions are perishable — cite each lab's current framework.)*

`★ Insight ─────────────────────────────────────`
- **Assess before deploy, red-team continuously.** Impact assessments *reason*
  about who gets hurt (and decide how much governance a system needs);
  red-teaming *tries* to hurt it — and because model-behavior failures are
  emergent and unpatchable, red-teaming is an ongoing practice, not a one-time
  test. OWASP and ATLAS give you the checklist so you're not brainstorming
  attacks from scratch.
- **The "if-then" frontier pattern is pre-commitment against your own future
  pressure** — define the dangerous-capability threshold and the triggered
  safeguard in advance, so the safety call isn't made in the heat of a launch.
  It's the same "decide the bar before the result" discipline as a pre-registered
  eval gate.
`─────────────────────────────────────────────────`

## Next

→ [Operationalizing governance](05-operationalizing-governance.md) — turning all
of this into a program that actually runs.
