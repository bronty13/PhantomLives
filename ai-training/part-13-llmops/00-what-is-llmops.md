---
title: What is LLMOps, and the productionization gap
module: 13 — LLMOps / Productionization & Observability
lesson: 00
est_time: 30 min reading
last_reviewed: 2026-06-26
tags: [ai, llmops, production, mlops, lifecycle]
---

# What is LLMOps, and the productionization gap

You've reached the operational module. Everything before this taught you to
*build* an AI system — choose the model, prompt it, ground it, make it agentic,
evaluate it, control its cost, run it locally, extend it to new modalities and
code, design its UX, and govern it. This module is about the unglamorous reality
that sits between "it works on my machine" and "it serves real users reliably at
3am": **LLMOps — the engineering discipline of operating LLM-powered applications
in production.**

It's a synthesis module. Pieces of it live in
[Module 7 (cost)](../part-07-cost-and-latency/00-fundamentals-and-the-triangle.md),
[Module 8 (serving)](../part-08-local-inference/04-serving-at-scale-vllm.md),
[Module 5 (eval/monitoring)](../part-05-evaluation/05-evaluation-in-production.md),
and [Module 12 (governance)](../part-12-governance/05-operationalizing-governance.md).
This module connects them into the operational spine.

---

## The productionization gap

There's a well-worn truth in this field: **it's easy to make something cool with
an LLM, and very hard to make it production-ready.** A weekend demo is a single
happy-path API call. Production is everything around that call — what happens when
the provider is down, when the response is a confident lie, when costs spike 10×
overnight, when you need to know *why* a specific answer went wrong three days
ago, when a prompt tweak silently degrades quality for a subset of users.

LLMOps is the engineering rigor that closes that gap. And the gap is real because
operating an LLM app differs structurally from operating either a normal web
service or a classic ML system.

---

## LLMOps vs. MLOps: the inversion

Classic **MLOps** is organized around a model *you train and own*: gather data →
train → evaluate on fixed metrics (accuracy, F1, AUC) → deploy the weights →
monitor for data drift. Most LLM applications **invert this**, and four
properties fall out of the inversion:

1. **You consume, you don't train.** The model is a foundation model behind
   someone else's API. Your engineering effort moves from *training* to
   *orchestration* — prompts, context, retrieval, tools, routing. **The artifact
   you actually ship is the prompt + context + retrieval + tool config, not
   weights.** That artifact needs versioning and testing just like code (see
   [lesson 04](04-continuous-improvement-and-lifecycle.md)).
2. **Non-determinism is inherent, not a bug.** The same input can produce
   different output. `temperature=0` only *mostly* helps — numerical and hardware
   sources of nondeterminism remain. Your tests, SLOs, and monitoring all have to
   accommodate a system that won't give the same answer twice
   ([lesson 03](03-reliability-engineering.md)).
3. **Cost is token-based and inference-dominated.** Where MLOps cost lives in
   *training*, LLMOps cost lives in *inference* — every request, forever, billed
   by the token. Cost is a first-class operational signal, not an afterthought
   (the whole of [Module 7](../part-07-cost-and-latency/01-token-economics.md), and
   [lesson 05](05-ops-at-scale.md) here).
4. **A hard external-API dependency.** Your reliability is now partly someone
   else's uptime, rate limits, and deprecation schedule. That's a vendor-risk and
   resilience problem MLOps mostly didn't have ([lessons 01](01-the-llm-gateway-pattern.md)
   and [03](03-reliability-engineering.md)).

And a fifth, from [Module 5](../part-05-evaluation/00-the-eval-mindset.md):
**evals replace fixed metrics.** There's no single accuracy number; quality is
measured by an eval suite plus real user feedback.

> **Don't oversell the gap.** CI/CD, versioning, monitoring, governance, and
> feedback loops all *carry over* from MLOps and classic software ops. LLMOps
> **extends** them; it doesn't replace them. The new work is wrapping engineering
> rigor around the five properties above — not throwing out everything you knew.

---

## What "production-ready" actually means

The pillars that separate a production LLM app from a demo — each a lesson or a
cross-link in this module:

| Pillar | Covered in |
|---|---|
| **Reliability** against silent failures (a 200 OK that's wrong) | [lesson 03](03-reliability-engineering.md) |
| **Observability** — traces, cost, quality, the full agent trace tree | [lesson 02](02-observability-and-tracing.md) |
| **Evals as a quality gate** in CI, not vibes | [lesson 04](04-continuous-improvement-and-lifecycle.md) + [Module 5](../part-05-evaluation/05-evaluation-in-production.md) |
| **Real-time guardrails** distinct from batch evals | [Module 12](../part-12-governance/04-risk-assessment-and-red-teaming.md) |
| **Cost control** — budgets, attribution, hard caps | [lesson 05](05-ops-at-scale.md) |
| **Latency / throughput SLOs** | [lesson 03](03-reliability-engineering.md) + [Module 7](../part-07-cost-and-latency/04-latency-engineering.md) |

A useful distinction: **evals run in batches; guardrails act in real time.** An
eval tells you, offline, whether quality regressed; a guardrail prevents an
unsafe or non-compliant response from reaching the user *right now*. You need
both.

---

## The lifecycle: an inner and an outer loop

LLMOps is iterative, not a pipeline you run once. A useful framing (Microsoft's)
splits it into two loops:

- **Inner loop (develop):** data curation → experimentation (prompt engineering,
  retrieval, model selection, fine-tuning) → evaluation. Fast, offline, where you
  iterate on quality.
- **Outer loop (operate):** validate & deploy (including A/B) → inference
  (low-latency, high-throughput serving) → monitor (anomaly/privacy alerts,
  response review) → **feedback & data collection.**

And the loops *close*: the feedback and production traces from the outer loop
enrich the eval datasets of the inner loop — which is exactly
[Module 11's feedback flywheel](../part-11-product-ux/05-onboarding-and-the-feedback-flywheel.md)
and [Module 5's production-eval](../part-05-evaluation/05-evaluation-in-production.md),
viewed as an operational cycle. The rest of this module walks the outer loop:
the gateway (01), observability (02), reliability (03), the deploy/improve cycle
(04), and ops at scale (05).

`★ Insight ─────────────────────────────────────`
- **LLMOps inverts MLOps:** you ship the prompt/context/tool config, not weights;
  the system is non-deterministic; cost lives in inference forever; and you carry
  a hard dependency on someone else's API. Production rigor is engineering wrapped
  around those properties — *extending* classic ops, not replacing it.
- **"Production-ready" is the set of things a demo skips** — silent-failure
  reliability, observability, eval gates, real-time guardrails, cost caps, and
  SLOs. The gap between cool-demo and production is exactly this module.
`─────────────────────────────────────────────────`

## Next

→ [The LLM gateway pattern](01-the-llm-gateway-pattern.md) — the single chokepoint
that makes the rest of LLMOps configurable.
