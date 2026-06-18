---
title: Latency engineering
module: 07 — Cost & Latency Engineering
lesson: 04
est_time: 30 min reading
last_reviewed: 2026-06-18
tags: [ai, latency, ttft, streaming, throughput]
---

# Latency engineering

Latency is half the user experience and a hard constraint for anything interactive. This
lesson is how to make responses fast — and *feel* fast — and the throughput↔latency tension
you hit when self-hosting.

## The anatomy: where the time goes

Standard metrics (every provider and inference engine uses these):

| Metric | Measures |
|---|---|
| **TTFT** — time to first token | Submit → first output token (queuing + prompt processing + network) |
| **TPOT / ITL** — time per output token | Average gap between tokens during generation |
| **Throughput** — tokens/sec | System-wide output rate |
| **End-to-end** | `TTFT + generation time` |

Inference has two physically distinct phases:

- **Prefill** — process the *entire prompt in parallel* to build the KV cache and emit the
  first token. **Compute-bound, happens once → this is TTFT.** Grows with prompt length.
- **Decode** — generate output tokens **one at a time**, each attending over all prior
  tokens. **Memory-bandwidth-bound, repeats once per output token → this is TPOT.**

> **The load-bearing fact:** because prefill runs once but decode runs per output token,
> **generation usually dominates end-to-end latency, and latency scales with output length.**
> The biggest *real* latency lever you control is how many tokens the model emits.

## Latency-reduction techniques (by leverage)

### Streaming — the biggest *perceived*-latency lever
Send tokens as they're generated so the user sees output starting at TTFT instead of waiting
for the whole response. It doesn't reduce *real* total time, but it transforms the felt
experience — **the single most important UX move.** Pair with loading/skeleton indicators.

### Reduce output tokens — the biggest *real* lever
Since decode dominates, cutting output length cuts latency most. Prompt for conciseness, set
`max_tokens` (a blunt cap — truncates mid-word; good for short/multiple-choice), use **stop
sequences** to end cleanly, and note models count *tokens not words* (limit by
sentences/paragraphs, not "in 100 words"). This is the same lever as cost
([lesson 01](01-token-economics.md)) — shorter output is cheaper *and* faster.

### Model / effort choice
Pick the smallest, fastest tier that meets quality (the fast tier can be several times
faster than the flagship — [Module 1](../part-01-model-landscape/01-frontier-proprietary-models.md)),
and on reasoning models **lower the thinking effort** for latency-sensitive work.

### Prefix caching cuts TTFT
A cached prompt prefix skips re-processing those input tokens, **reducing TTFT directly**
(reported up to ~85% latency reduction on long prompts) — caching is a *cost and latency*
win at once ([lesson 02](02-caching.md)).

### Parallelize independent calls
Independent calls (fan-out subtasks, multi-doc processing, independent tool calls) should run
**concurrently**, so wall-clock collapses to the slowest call instead of the sum.

### Speculative decoding
A small draft model proposes tokens the big model verifies in one pass — ~2–3× decode
speedup with **identical output** (mostly a self-hosting/serving lever).

### Mind the reasoning-model TTFT
Reasoning models think (often a long internal chain) **before** the first visible token, so
TTFT can stretch from seconds to *minutes*. For latency-sensitive paths, **gate reasoning
on/off per task** or cap the thinking budget — don't pay extended-thinking latency on a
lookup.

### Region & network
Network round-trip and provider-side queuing are part of TTFT — co-locate with the provider
region and reuse connections.

## Throughput vs. latency (when you self-host)

If you run your own inference (vLLM, TensorRT-LLM, SGLang, TGI), you hit a core tension:

- LLM decode is **memory-bandwidth-bound**, so **batching more requests together raises
  throughput** (weight loads are amortized across the batch) — *almost free* until the GPU
  saturates, after which per-request latency climbs.
- **Continuous (in-flight) batching** — evicting finished sequences and injecting new ones
  every step instead of waiting for a whole static batch — is the key technique; it can raise
  throughput by an order of magnitude *and* often improves latency (new requests join
  immediately) until you're near saturation.
- Engines specialize: **vLLM** (PagedAttention + continuous batching + prefix caching) is
  throughput-oriented; **TGI** can show lower *tail* latency for interactive single-user use.
  **Quantization** raises achievable throughput by shrinking memory pressure.

So the self-hosted dial is: **batch harder for throughput-per-dollar, or keep batches small
for low per-request latency** — you tune to your SLO. (The *economics* of that — utilization,
cost-per-token, build-vs-buy — are [lesson 05](05-production-economics-and-build-vs-buy.md).)

## The mental model

Optimize **perceived** latency first (stream — it's nearly free and users feel it most), then
**real** latency (shorter output, faster/smaller model, less thinking, cached prefix,
parallelism). On hosted APIs those are your levers; self-hosting adds the batching dial, which
trades latency for throughput-per-dollar.

---

## Next

→ [Production economics & build-vs-buy](05-production-economics-and-build-vs-buy.md)
