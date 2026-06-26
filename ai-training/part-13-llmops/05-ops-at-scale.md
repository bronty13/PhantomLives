---
title: Ops at scale
module: 13 — LLMOps / Productionization & Observability
lesson: 05
est_time: 35 min reading
last_reviewed: 2026-06-26
tags: [ai, llmops, secrets, cost-governance, pii, platform-team]
---

# Ops at scale

The previous lessons covered the mechanics — gateway, observability, reliability,
the deploy/improve loop. This capstone is about running all of it when *many
teams* build *many features* on shared LLM infrastructure: secrets, cost
governance, data handling, and the organizational pattern that ties them
together. It closes Module 13 and, with it, the course.

> ⚠️ **Dated snapshot — June 2026.** Tooling and provider data-retention terms are
> a snapshot; the principles are durable. Re-verify the provider privacy/retention
> terms before relying on them — they're legally binding and they change.

---

## The durable principle: govern at the center, consume at the edge

The organizing idea of LLMOps at scale: **governance centralized at a chokepoint,
consumption decentralized to product teams.** A central platform owns the shared
substrate (gateway, observability, evals, prompt registry, guardrails); product
teams self-serve within it. Everything below is an instance of that split.

---

## Secrets and key management

Never hardcode provider keys, and never scatter them through app config. The
durable pattern:

- **Apps hold a *reference*, not the secret.** The gateway or a secret manager
  fetches the real provider key at runtime. The application never sees it.
- **Scoped virtual keys.** Instead of handing every service the master provider
  key, the gateway mints **virtual keys** — per-team or per-feature credentials
  with their own model-access restrictions, rate limits, and budget caps, all
  derived from one underlying key. A leaked virtual key is scoped and revocable;
  a leaked master key is a catastrophe.
- **Short-lived, rotatable credentials.** Dynamic-secret systems can create,
  rotate, and revoke provider credentials with a TTL, so apps use short-lived keys
  and rotation is automatic rather than a fire drill.

This is the [Module 12 documentation/accountability](../part-12-governance/03-documentation-and-accountability.md)
and [Module 10 secret-leakage](../part-10-coding-agents/05-security-and-failure-modes.md)
concerns met with infrastructure: scoped, referenced, rotatable keys at the
gateway.

---

## Cost governance: attribution and *hard* budgets

[Module 7](../part-07-cost-and-latency/05-production-economics-and-build-vs-buy.md)
covered the economics; at scale the operational additions are **attribution** and
**enforcement**.

- **Attribution is the foundation.** Tag every request with its customer, feature,
  team, and environment, so cost becomes a *filterable dimension* — you can answer
  "which feature is burning the budget?" and "what does this customer cost to
  serve?" Without attribution, cost is one undifferentiated number you can't act
  on.
- **Enforce *hard* budgets at the gateway — because provider budgets are usually
  *soft*.** This is the trap worth flagging loudly: a provider's project budget
  often only fires an *alert* at 100% and **keeps serving requests**. If you need
  spend to actually *stop*, that hard cap has to live at the gateway (a virtual
  key that auto-expires when its budget is hit). Relying on the provider's budget
  as a cap is how a runaway loop produces a five-figure surprise bill overnight.

The [Module 11 feedback-loop](../part-11-product-ux/05-onboarding-and-the-feedback-flywheel.md)
caution applies here too: tie cost governance to outcomes, not to a metric you
can game.

---

## Data handling: PII, retention, and the provider's terms

Your prompts and logs are full of user content ([lesson 02](02-observability-and-tracing.md)),
which makes data handling a compliance obligation ([Module 12](../part-12-governance/02-data-privacy-and-governance.md)),
not a preference. Two layers:

**Your side:**
- **Redact PII *before* you log** — ideally before the request leaves your
  perimeter. Gateways can mask PII for the observability sink without altering the
  live request, so you keep debuggability without storing raw personal data.
- **Set retention TTLs** on logs and traces — no indefinite retention (a
  [Module 12 principle](../part-12-governance/02-data-privacy-and-governance.md)).

**The provider's side** (re-verify — these are dated and legally binding):
- Major providers **do not train on API data by default** and delete inputs/
  outputs after a window (commonly ~30 days) unless legally required.
- **Zero Data Retention (ZDR)** is available for sensitive workloads but is
  typically *contractual and per-organization*, not a self-serve toggle — and even
  under ZDR, policy-flagged data may be retained for a period.
- **Data residency** controls (pin inference to a region/data zone) matter for
  [Module 12 jurisdictional](../part-12-governance/01-the-regulatory-landscape.md)
  requirements; providers expose region routing for this.

The durable rule: **know your provider's no-train / retention / residency posture
*before* you send regulated data, and pin it in your contract — the default terms
are not the same as your compliance obligations.**

---

## The central AI-platform team

The organizational pattern that makes all of this sustainable: a **central
AI-platform team** owns the shared substrate — the gateway, observability, the
eval harness, a shared prompt registry, and guardrails / policy-as-code — so that
**product teams self-serve**: they mint scoped keys, ship within budgets, and get
logging, redaction, fallback, and cost tracking *for free* by routing through the
platform.

This realizes "governance centralized, consumption decentralized": the platform
applies controls **at the gateway** (the [lesson 01](01-the-llm-gateway-pattern.md)
enforcement point), and product teams plug in without each re-implementing
reliability, observability, and compliance. Output validation, prompt-injection
detection, and guardrails become **shared platform concerns**, not per-app
reinventions — which is both more secure and far less duplicated effort.

---

## Where this lands — Module 13, and the course, complete

LLMOps is the operational synthesis of the whole course: it runs on
[Module 7's economics](../part-07-cost-and-latency/00-fundamentals-and-the-triangle.md)
and [Module 8's serving](../part-08-local-inference/04-serving-at-scale-vllm.md),
enforces [Module 5's evals](../part-05-evaluation/05-evaluation-in-production.md)
and [Module 12's governance](../part-12-governance/05-operationalizing-governance.md),
serves [Module 11's UX](../part-11-product-ux/01-latency-and-perceived-performance.md),
and operates the [Module 4](../part-04-agents-and-tool-use/06-evaluating-and-operating-agents.md)
and [Module 10](../part-10-coding-agents/01-agentic-coding-workflows.md) agents you
built. It's where "I built an AI thing" becomes "I run an AI product."

`★ Insight ─────────────────────────────────────`
- **Govern at the center, consume at the edge.** Scoped virtual keys, per-request
  cost attribution, PII redaction, and policy-as-code all live at the gateway the
  platform team owns — so product teams ship fast *and* safely without each
  reinventing reliability and compliance.
- **The two traps that bite at scale: soft provider budgets and default data
  terms.** A provider budget that only *alerts* won't stop a runaway bill — put
  the hard cap at the gateway; and the provider's default no-train/retention terms
  are not your compliance posture — pin ZDR/residency in the contract before
  sending regulated data.
`─────────────────────────────────────────────────`

## Course complete

This completes **Module 13 — LLMOps / Productionization & Observability**, and the
curriculum. The full arc: choosing models → prompting → RAG → agents → evaluation
→ fine-tuning → cost/latency → local inference → multimodal → coding agents →
product/UX → governance → **running it all in production.**

→ Back to the [curriculum index](../CURRICULUM.md). Keep the frameworks, re-verify
the dated catalogs as you use them, and build things that work — and keep working.
