---
title: Production economics & build-vs-buy
module: 07 — Cost & Latency Engineering
lesson: 05
est_time: 30 min reading
last_reviewed: 2026-06-18
tags: [ai, cost, finops, build-vs-buy, self-hosting]
---

# Production economics & build-vs-buy

The final discipline: seeing where the money goes, putting guardrails on it, and making the
biggest infrastructure decision — **call an API or run your own GPUs?**

## Monitor & attribute (you can't control what you can't see)

An end-of-month invoice is useless for optimization. You need **request-level attribution**:

- **Tag every call** with `user_id`, `feature`, `route`, `model`, `team`.
- **Capture it centrally** — an **LLM gateway/proxy** (a "single front door" that auto-logs
  tokens, model, cost, and tags) or **OpenTelemetry** spans tying cost to the full request
  ([Module 4, lesson 06](../part-04-agents-and-tool-use/06-evaluating-and-operating-agents.md)'s
  observability, extended to dollars).
- **Dashboard** spend by feature, model, route, and customer; input-vs-output token trends;
  and cost-per-task as a unit-economics metric.

## Budgets & guardrails (visibility ≠ enforcement)

- **Budget alerts** on cumulative thresholds (per user/feature/day).
- ⚠️ **Dashboards only show; a gateway that blocks the request before the provider call is
  what *enforces*.** For agents, **max-iteration / max-token caps are mandatory** cost
  controls, not nice-to-haves ([Module 4, lesson 05](../part-04-agents-and-tool-use/05-safety-security-and-reliability.md)) —
  a runaway loop is a runaway bill.

## Build vs. buy: API vs. self-host

The biggest decision, and the most misunderstood. The break-even estimate varies **~100×
across sources** because it hinges almost entirely on one variable: **GPU utilization.** So
learn the *mechanism*, not a magic number.

**The two cost structures:**

| | **API (buy)** | **Self-host (build)** |
|---|---|---|
| Cost shape | Pure **variable** ($/token) | Mostly **fixed** (GPU + the dominant hidden cost: **staffing**) |
| Scales | Linearly with traffic | Stepwise (whole GPUs) |
| Marginal token | Full price | ~Free (once the GPU is paid for) |
| Ops burden | ~None | High — **personnel is ~70–80% of self-hosting TCO** |

**Utilization is make-or-break.** A self-hosted GPU's cost-per-token is `GPU $/hr ÷ tokens it
actually produces`. At ~70% utilization self-hosting can be very cheap; at ~10% utilization
the *same* hardware can be **several times more expensive than a premium API** — idle GPUs
destroy the economics. The vivid version: at low volume on an under-fed GPU, self-hosting can
be **dozens-to-hundreds of times more expensive** than an API.

**Rough heuristic (treat as a range, not law):** under ~1M tokens/day → **API is almost
always cheaper**; sustained 10M+ tokens/day at high utilization → **self-hosting can pay back
in months.** The crossover is sometimes cited around ~$500k/yr of API spend — but it moves
with your utilization, model size, and hardware, so **model your own numbers.**

**Non-cost reasons to self-host:** data must stay in your VPC (compliance/HIPAA), you run a
proprietary fine-tuned model with no API ([Module 6](../part-06-fine-tuning/00-fundamentals-and-when-to-fine-tune.md)),
or you need full control. Sometimes these decide it regardless of the token math.

> **The pragmatic answer is usually hybrid:** route by difficulty and sensitivity — a cheap
> fast API tier for easy queries, a strong API for hard ones, a self-hosted small model for
> high-volume batch or sensitive data. This is the routing of
> [lesson 03](03-model-selection-and-routing.md) applied to the build-vs-buy axis, and it's
> how teams report cutting LLM bills the most.

## Batch for offline work

Anything not real-time → the **batch API** (~50% off, [lesson 01](01-token-economics.md)).
The most straightforward cost cut for evals, bulk processing, and report generation.

## Autoscaling & capacity planning

Self-hosting scales in **whole-GPU steps**, while API scales smoothly — so bursty traffic
creates idle-GPU risk that erases savings. If you self-host: size to a utilization target
(~70%+), keep a redundancy buffer, and use autoscaling/spot capacity to track demand. APIs
hand you elastic scale as someone else's problem (within rate limits).

## FinOps for AI

The discipline now has a name: tokens are the new cost unit ("tokenomics"). The practices
pull this whole module together:

1. **Attribute** every call to a cost owner (tags).
2. **Dashboard** unit economics — cost per user / feature / task.
3. **Budget + alert + enforce** at the gateway.
4. **Continuously optimize** — cheapest model that passes eval, cache, batch, route.

## The whole module, in one line

**Measure cost and latency per request → cut tokens (shorter output, trimmed context) → cache
the repeated parts → right-size and route by difficulty → stream and shorten for latency →
batch the async work → and decide API-vs-self-host by your actual GPU utilization, defaulting
to a hybrid — all validated against your eval so quality never silently slips.**

That closes the operational arc: the earlier modules made the system *good*; this one makes
it *good, fast, and affordable at scale.*

---

← [Latency engineering](04-latency-engineering.md) · ↑ [Module index](../CURRICULUM.md)
