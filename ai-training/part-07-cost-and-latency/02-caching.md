---
title: Caching
module: 07 — Cost & Latency Engineering
lesson: 02
est_time: 30 min reading
last_reviewed: 2026-06-18
tags: [ai, cost, caching, prompt-caching, semantic-cache]
---

# Caching

Caching is the **single biggest cost lever** for any app with repeated context — and it cuts
latency too. The course has touched it twice ([prompt caching in Module 2](../part-02-prompt-engineering/03-advanced-patterns.md),
[caching retrieved context in Module 3](../part-03-rag/05-evaluation-security-and-production.md));
here's the full picture, with the economics.

## 1. Prompt / prefix caching — the dominant lever

**What it is:** the provider caches the processed form of a **stable prefix** of your prompt,
so the next request with the *same prefix* bills those tokens at a deeply discounted "cached
read" rate instead of full price.

**The one invariant — it's a prefix match.** The cache key is the exact bytes up to a
breakpoint, and **any byte change anywhere in the prefix invalidates everything after it.**
Render order is `tools → system → messages`, so put **stable content first** (frozen system
prompt, deterministic tool list, few-shot examples, RAG corpus) and **volatile content last**
(the user's varying question, timestamps, per-request IDs).

**Economics (Anthropic shape):**
- Cache **reads** ≈ **0.1× input** (~90% cheaper).
- Cache **writes** ≈ 1.25× input (5-min TTL) or 2× (1-hour TTL).
- **Break-even:** ~2 requests on the 5-min TTL, ~3 on the 1-hour TTL — so caching pays off
  almost immediately for any reused prefix.
- Minimum cacheable prefix is model-dependent (silently won't cache below it); max 4
  breakpoints; default TTL 5 min (refreshed on hit).

**Provider differences worth knowing (a real "shape" difference):**
- **Anthropic** — explicit (`cache_control`), ~90%-off reads, TTL refresh-on-use.
- **OpenAI** — **automatic** (no code), prefixes >1,024 tokens, but a shallower **~50%-off**
  read.
- **Google Gemini** — ~90%-off reads **plus a per-hour storage fee** (you pay to keep it
  warm).

**What silently breaks it (audit checklist):** `datetime.now()`/UUIDs in the system prompt;
unsorted `json.dumps()` (sort keys); a tool set that varies per request (tools render
first — any change nukes everything); switching models mid-session (caches are
model-scoped); user/session IDs interpolated into the prefix. **Verify it's working:** check
`usage.cache_read_input_tokens > 0` across identical-prefix requests — if it's zero, a silent
invalidator is at work. (Full audit table: [Module 2, lesson 03](../part-02-prompt-engineering/03-advanced-patterns.md).)

**When it applies:** a large fixed system prompt, RAG documents reused across questions,
multi-turn conversations, agent tool definitions. **When it doesn't:** prompts that differ
from the very first byte every request — there's no reusable prefix, so you'd only pay the
write premium.

## 2. Semantic / response caching — skip the call entirely

**What it is:** embed the incoming query and, if it's *semantically similar* (cosine above a
threshold) to a past query, **return the stored response without calling the model at all** —
a **100% saving on a hit**, not just a discount.

**The trade-off is correctness.** Prefix caching has *zero* correctness risk (exact match);
semantic caching can return a wrong cached answer for a query that was *close but not
equivalent* — a **false hit**. The threshold is the critical dial:

- **Low threshold** → more hits, more false positives (wrong answers).
- **High threshold** → fewer false hits, fewer hits (more model calls).
- **Practical guidance:** start conservative (~0.92–0.97 cosine), monitor the false-positive
  rate for a couple of days, then nudge the threshold in small steps. Use it for **high-
  volume, repetitive, low-stakes** queries (FAQs, support deflection); **avoid** it where a
  wrong answer is costly. (Reference: GPTCache-style systems.)

## 3. Embedding caching — the free one

Embeddings are deterministic per model, so **cache embedding vectors keyed by a hash of the
input text** (invalidate on model change). Zero correctness risk; avoids re-paying to embed
documents you've already indexed. A prerequisite for cheap RAG *and* semantic caching.

## 4. KV cache & Cache-Augmented Generation (CAG) — briefly

- **KV cache** is the model-internal attention cache built during prefill; reusing it is the
  *mechanism* that makes prompt/prefix caching cheap (the discounted "read" is a KV-cache
  reuse). You don't manage it directly on hosted APIs.
- **CAG** = deliberately preload an entire (small, static) knowledge base into context and
  precompute its cache once, then answer every query against it with no retrieval step —
  prefix caching applied to a whole corpus. Trade-off: the cache is a point-in-time snapshot
  (stale until rebuilt), so it suits small, stable corpora — the long-context end of the
  [RAG-vs-long-context decision](../part-03-rag/00-rag-fundamentals.md).

## The caching hierarchy (savings vs. risk)

| Cache | Saving | Correctness risk |
|---|---|---|
| **Embedding** | Avoids re-embedding | None (deterministic) |
| **Prompt / prefix** | ~50–90% of cached input | **None** (exact match) |
| **Semantic / response** | ~100% on a hit (skips the call) | **Real** — false hits, threshold-dependent |

Reach for the zero-risk caches first (embedding, prefix); add semantic caching only for
low-stakes, high-repeat traffic with monitoring on the false-hit rate.

---

## Next

→ [Model selection & routing](03-model-selection-and-routing.md)
