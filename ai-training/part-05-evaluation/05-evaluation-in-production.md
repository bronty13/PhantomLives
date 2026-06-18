---
title: Evaluation in production
module: 05 — Evaluation
lesson: 05
est_time: 35 min reading
last_reviewed: 2026-06-18
tags: [ai, evaluation, statistics, ab-testing, monitoring, ci]
---

# Evaluation in production

The final discipline: doing eval **rigorously** (a number is not a result) and
**continuously** (every change, and on live traffic). This lesson covers the statistics that
keep you honest, A/B testing, CI/regression gating, and production monitoring.

## Part 1 — Statistics: a number is not a result

> **Evaluations are experiments.** A bare "87%" with no uncertainty is not a result you can
> act on. [(Anthropic — Adding Error Bars to Evals)](https://www.anthropic.com/research/statistical-approach-to-model-evals)

### Why a 2-point win on 100 examples is usually noise
For a pass rate, the standard error is `SEM ≈ √(p(1−p)/n)`. At `p≈0.5, n=100`, SEM ≈ 5
points, so the 95% confidence interval is roughly **±10 points**. A 2-point gap sits well
inside the noise — it tells you nothing. Two sources of variance compound: *which examples*
you happened to sample, and *LLM nondeterminism* (sampling/temperature).

### The discipline
- **Report a confidence interval, not just a mean** (mean ± 1.96 × SEM).
- **Use clustered standard errors** when questions are grouped (many questions per
  document) — naive SEMs understate uncertainty, sometimes by 3×.
- **Compare on paired differences** — run both systems on the *same* questions and analyze
  the per-question delta; this cancels question-difficulty variance and is far more
  sensitive (the eval analogue of a paired t-test / McNemar's test).
- **Reduce within-question variance** — resample each question a few times and average.
- **Bootstrap** when the metric isn't a clean proportion (F1, ROUGE, judge scores): resample
  per-example scores ~10,000×, take the 2.5th/97.5th percentiles. To compare two systems,
  **bootstrap the paired delta** — significant only if the CI lower bound > 0.
- **Power first** — pick `n` so the CI is narrower than the difference you care about.

Practitioner sample-size heuristics (not formal power calcs): ~10–20 catches only
catastrophic regressions; ~50–100 catches ~5–10pt effects; **hundreds-to-thousands** to
resolve a few points.

### `pass@k` vs `pass^k` — capability vs reliability
(Introduced for agents in [Module 4, lesson 06](../part-04-agents-and-tool-use/06-evaluating-and-operating-agents.md);
here's the math.)

```
pass¹  = E[p]            mean single-attempt success
pass@k = E[1−(1−p)^k]    ≥1 of k succeeds → RISES with k   (capability / coverage)
pass^k = E[p^k]          ALL k succeed   → FALLS with k    (reliability / consistency)
```

A 70%-per-attempt agent has **pass@3 ≈ 0.97** (looks ready) but **pass^3 ≈ 0.34** (a
disaster in production). Use **pass@k** when you can verify before using the output (code
with unit tests, retrieval); use **pass^k** when one failure is costly and the system can't
self-check (customer-facing agents). **Report both** — the mean hides reliability.

## Part 2 — A/B testing

*Offline eval proves a prompt **can** work; A/B proves it **does** for real users.*

- **Offline A/B:** matched pairs (same inputs) + pairwise/arena judging + a bootstrap CI on
  the delta. Keep the winner only if the delta is significant.
- **Online A/B:** tie the test to a **real business metric**, not a proxy. A canonical example
  selected a cheaper model because it *matched* the incumbent's conversion rate (a
  **non-inferiority** test with pre-specified α/power) — business-metric equivalence, not
  benchmark superiority, drove the decision. Use proper proportion tests; don't peek at
  p-values early.
- **Shadow testing** — send each request to both control (shown) and candidate (logged,
  scored offline). Real-distribution data, zero user-facing risk.

## Part 3 — Regression testing & CI

Make eval a **deploy gate**, the way unit tests gate code:

- Keep a small, fast **CI eval set** (~100+ examples) covering core features, edge cases,
  and a **regression test for every past production bug**.
- **Prefer deterministic checks in CI** ([lesson 02](02-grading-methods.md)) — fast, cheap,
  no judge nondeterminism. Run heavy LLM-judge evals less often.
- A CI job runs the eval on each change and **blocks regressions**.
- **Gate on "no statistically significant regression vs. baseline"** (the paired-delta CI
  from Part 1), *not* on an absolute pass rate — and don't optimize for a green board. If
  you're passing 100%, your set is too easy; ~70% is often where it's informative.

## Part 4 — Online / production monitoring

Offline eval can't see the real input distribution; production monitoring can. Score a
**sample** of live traffic after the fact.

- **What to score:** cheap heuristics (JSON valid? citation present? refused?), guardrail
  signals (PII/toxicity/injection), and a sampled LLM-judge rubric.
- **Two timing modes — don't conflate:** **real-time guardrails** sit inline, can block or
  rewrite, must be cheap; **async online evals** run off the hot path so heavy judging never
  adds user latency.
- **Sample** (~2% baseline, more on high-risk routes) and **report sample size + CIs** so a
  low-volume slice's "drop" isn't mistaken for signal.
- **Treat a production LLM-judge as a trend signal, never ground truth** — recalibrate it
  against fresh human labels when the judge, rubric, or traffic shifts
  ([lesson 03](03-llm-as-judge.md)).
- **User feedback:** *explicit* (thumbs/stars) is high-signal-of-intent but noisy and sparse;
  *implicit* (task completion, abandonment, retries/rephrasing, copy-paste, edits) is
  higher-volume and often more honest.
- **Drift detection:** watch **input drift** (the distribution shifts), **quality drift**
  (rising refusals, longer outputs, falling judge scores), and **model drift** (a provider
  silently updates the model). **Slice every metric by model / route / prompt version and
  alert when it drops by more than the noise** (the CI, not an absolute threshold).

## Part 5 — Tooling (neutral, June 2026)

> ⚠️ Tools, ownership, and pricing change fast — verify before standardizing on one.

| Job | Tools |
|---|---|
| Research benchmarking | EleutherAI **lm-evaluation-harness**, Stanford **HELM**, UK AISI **Inspect** |
| Product / app evals | **LangSmith**, **Braintrust**, **DeepEval**, **promptfoo** |
| CI gating | **promptfoo**, **DeepEval**, **Braintrust** |
| RAG-specific | **Ragas** ([Module 3](../part-03-rag/05-evaluation-security-and-production.md)) |
| Red-teaming | **promptfoo** (OWASP-LLM coverage), **Inspect** |

A spreadsheet plus a grading script is a perfectly good start — the **discipline matters
more than the tool.**

## The whole module, in one line

**Make eval the core loop → build a private, task-specific, contamination-free golden set →
grade with the cheapest reliable method (validating any LLM judge against humans) → read
benchmarks critically as a starting signal only → and ship behind statistically honest,
continuous, production-monitored evaluation.**

---

← [Benchmarks & the landscape](04-benchmarks-and-the-landscape.md) ·
↑ [Module index](../CURRICULUM.md)
