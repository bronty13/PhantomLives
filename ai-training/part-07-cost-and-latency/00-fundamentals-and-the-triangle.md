---
title: Fundamentals & the cost/latency/quality triangle
module: 07 — Cost & Latency Engineering
lesson: 00
est_time: 25 min reading
last_reviewed: 2026-06-18
tags: [ai, cost, latency, economics]
---

# Fundamentals & the cost/latency/quality triangle

A system can be smart, cheap, and fast — pick two. This module is about engineering the
*best affordable, fast-enough* configuration that still meets your quality bar. It's the
operational synthesis of the whole course: the levers here are caching (deepening
[Module 2](../part-02-prompt-engineering/03-advanced-patterns.md)/[Module 3](../part-03-rag/05-evaluation-security-and-production.md)),
right-sizing/routing (extending [Module 1](../part-01-model-landscape/00-how-to-choose-a-model.md)
and [Module 4](../part-04-agents-and-tool-use/05-safety-security-and-reliability.md)),
distillation ([Module 6](../part-06-fine-tuning/01-methods.md)), and agent step-caps
([Module 4](../part-04-agents-and-tool-use/05-safety-security-and-reliability.md)) — measured
with [Module 5](../part-05-evaluation/00-the-eval-mindset.md)'s discipline.

## How LLM economics work (the shape)

APIs bill **per token**, quoted **per 1M tokens**, with **input and output priced
separately**. Three facts drive everything in this module:

1. **Output costs ~3–8× input.** Output tokens are generated sequentially and priced
   several times higher than input. → *Shorter output is often the cheapest win.*
2. **The API is stateless — you re-send the whole context every call.** System prompt +
   full history + RAG chunks + tool defs are **re-billed as input on every request**, so
   cost in a long chat/agent loop grows roughly **quadratically** with length. → *Context
   is the master knob.*
3. **Reasoning models bill hidden "thinking" tokens** as output, even when you never see
   them. → *The real cost of a reasoning call exceeds the length of its visible answer.*

(Details in [lesson 01](01-token-economics.md). Token counts are model-specific — use the
provider's own counter, not a generic estimator.)

## The triangle

```
            QUALITY
             /  \
            /    \
        COST ──── LATENCY
```

You optimize two corners at the third's expense:

- Push **quality** up → bigger model / more reasoning → **more cost, more latency.**
- Push **cost** down → smaller model / shorter output / cache → risk **quality**, helps latency.
- Push **latency** down → smaller model / less thinking / streaming → can cost quality.

**The engineering goal is not "cheapest" or "fastest" in the abstract — it's the cheapest,
fastest point that still passes your eval.** That's why every decision in this module routes
back through [Module 5](../part-05-evaluation/00-the-eval-mindset.md): you can only cut cost
or latency safely if you can *measure* that quality held.

## Why it matters

Per-call pennies are invisible in a demo and existential at scale. At a million requests a
day, the difference between the flagship and a right-sized model — or a 0% vs 90% cache hit
rate — is the difference between a viable product and a money-loser. Cost and latency *are*
the unit economics and the UX.

## The levers (a map of this module)

| Lever | Lesson | The idea |
|---|---|---|
| **Reduce tokens** | [01](01-token-economics.md) | Trim context, shorten output, batch async work |
| **Cache** | [02](02-caching.md) | Stop re-paying for repeated context (the biggest single lever) |
| **Right-size & route** | [03](03-model-selection-and-routing.md) | Match model cost to task difficulty, per request |
| **Latency engineering** | [04](04-latency-engineering.md) | Make responses fast and *feel* fast |
| **Production economics** | [05](05-production-economics-and-build-vs-buy.md) | Monitor, budget, and decide API vs. self-host |

They **compound**: a right-sized model, with a cached prefix, on batched async work, is
multiplicatively cheaper than the naive version.

## Measure first

You cannot optimize what you don't measure. Before tuning anything, instrument:

- **Cost per request / per task** — from **actual `usage`** (input + output + *reasoning*
  tokens), not the visible answer length. Reasoning tokens are the silent line item.
- **Latency metrics** — time to first token (TTFT), time per output token (TPOT), and
  end-to-end ([lesson 04](04-latency-engineering.md)).
- **Cache hit rate** — `cache_read_input_tokens > 0`? ([lesson 02](02-caching.md)).
- Attribute all of it per route / model / feature / user ([lesson 05](05-production-economics-and-build-vs-buy.md)).

Then change one lever, re-measure, and confirm quality held on your eval. Same loop as the
rest of the course — applied to dollars and milliseconds.

---

## Next

→ [Token economics](01-token-economics.md)
