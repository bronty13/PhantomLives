---
title: Model selection & routing
module: 07 — Cost & Latency Engineering
lesson: 03
est_time: 30 min reading
last_reviewed: 2026-06-18
tags: [ai, cost, routing, cascades, distillation]
---

# Model selection & routing

The principle in one line: **match model cost to task difficulty, per request.** Most
production traffic is easy; paying flagship prices for every query is the most common
avoidable cost. This lesson is the toolkit for *not* doing that.

This extends [Module 1's model-choice framework](../part-01-model-landscape/00-how-to-choose-a-model.md)
(pick the right tier) and [Module 4's per-step model choice](../part-04-agents-and-tool-use/05-safety-security-and-reliability.md)
(cheap model for routing, strong for hard subtasks) into a cost discipline.

## 1. Right-sizing — the cheapest model that passes your eval

Every provider ships tiers, and the cheap tier is often **5–25× cheaper** than the flagship
(nano/mini/flash/lite vs. Opus/GPT-5.5/Gemini-Pro). The method:

1. Build a representative eval set ([Module 5](../part-05-evaluation/01-building-eval-sets.md)).
2. Run the **cheapest tier first**.
3. Move up a tier **only when the eval fails.**

Classification, extraction, summarization, and routing usually pass on the small tier.
**Do not default to the flagship "to be safe"** — that's the single biggest source of
overspend. (Note: a coding assistant defaulting to a strong model for *its own* output is a
different decision than what *your app* should call at scale.)

## 2. Model cascades — cheap-first, escalate if needed (FrugalGPT)

A **cascade** tries a **cheap model first**, then a scoring function judges whether the answer
is good enough and **escalates to a more expensive model only if not.** The research result
(FrugalGPT) is striking: matching flagship quality at **up to ~98% lower cost** by exploiting
that model prices span two orders of magnitude.
[(FrugalGPT, 2023)](https://arxiv.org/abs/2305.05176)

- **Decides *after* generating** (try → check → maybe redo).
- **Needs a cheap, reliable quality scorer** — a bad scorer either escalates everything (no
  savings) or accepts bad cheap answers (quality regression).
- **Pays multiple calls on hard queries** → adds latency and cost on the tail.

## 3. Routers — decide up front, one call (RouteLLM)

A **router** is a classifier that picks the strong-vs-weak model **per query, before
generating** — trained on preference data (which model wins on which kind of prompt).
Reported results: large cost cuts (e.g. up to ~85% on some benchmarks) while retaining ~95%
of flagship quality. [(RouteLLM, 2024)](https://arxiv.org/abs/2406.18665)

**Router vs. cascade:**

| | Router | Cascade |
|---|---|---|
| Decides | **Before** generating | **After** (check, then escalate) |
| Calls | One | One or more (re-runs hard cases) |
| Failure mode | Misroutes silently, no recovery | Self-corrects, but double-pays |

Many production stacks combine them: route the obvious cases, cascade the ambiguous ones.

## 4. Distillation — permanent right-sizing

Train a small **student** model on a large **teacher's** outputs so it matches the teacher on
*your* task at a fraction of the inference cost (e.g. classic DistilBERT: ~40% smaller, ~60%
faster, ~97% of quality). This is the "small fine-tuned model beats a big prompted one" case
from [Module 6](../part-06-fine-tuning/01-methods.md) — an **upfront training cost to
permanently lower per-call cost**, best for a narrow, high-volume task. (It's fundamentally a
fine-tuning technique; here it's the "bake the savings in" option.)

## 5. Speculative decoding — faster, identical output

A small **draft model** proposes several tokens; the large **target model verifies them in
one forward pass**, accepting the correct prefix. Output is **identical** to the target model
(it's a speed optimization, not a quality trade-off), typically ~2–3× faster decode.
**Relevance to cost:** it's primarily a **latency / self-hosting throughput** lever
([lesson 04](04-latency-engineering.md)) — on hosted token-billed APIs it doesn't change your
per-token bill (the provider may already use it internally).

## The unifying principle (and compounding)

Right-sizing, cascades, routers, and distillation are four points on one line: **don't pay
frontier prices for non-frontier work.** They **compound** with the other levers — a mature
cost architecture layers:

```
right-sized default model
  → router for difficulty (strong model only when needed)
    → prompt cache on the shared prefix      (lesson 02)
      → semantic cache on repeat queries     (lesson 02)
        → batch API for anything async        (lesson 01)
```

Each layer multiplies the savings of the last — and every one is validated against the same
eval so quality doesn't quietly slip.

---

## Next

→ [Latency engineering](04-latency-engineering.md)
