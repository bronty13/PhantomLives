---
title: Latency & perceived performance
module: 11 — AI Product & UX Patterns
lesson: 01
est_time: 35 min reading
last_reviewed: 2026-06-26
tags: [ai, product, ux, latency, streaming, performance]
---

# Latency & perceived performance

LLMs are slow and variable — seconds for a chat reply, sometimes minutes for a
reasoning model. Yet the best AI products feel responsive. The resolution to that
apparent contradiction is the single most useful idea in AI UX: **perceived speed
is governed by early, continuous, legible feedback — not by total elapsed time.**
This lesson is the UX-layer companion to
[Module 7's latency engineering](../part-07-cost-and-latency/04-latency-engineering.md):
Module 7 made the system faster; this makes it *feel* fast.

---

## The response-time limits that still rule

Three thresholds, established in the 1960s–90s (Miller, Nielsen) and unchanged by
AI, explain everything that follows:

- **0.1s** — feels instantaneous; the user perceives direct manipulation.
- **1s** — keeps the user's flow of thought uninterrupted, though they notice the
  delay.
- **10s** — the limit of held attention. Beyond it, the user's mind wanders and
  you *must* show determinate progress or you lose them.

A related modern refinement, the **Doherty Threshold (~400ms)**: responses under
~400ms keep users in a productive flow state. This is why
**time-to-first-token (TTFT)** — not total response time — governs how an LLM
product *feels*. A reply that takes 8 seconds total but starts streaming in
300ms feels responsive; the same 8 seconds spent staring at a spinner feels
broken.

---

## Streaming: the highest-leverage AI-UX pattern

Autoregressive models emit tokens one at a time as they generate. **Streaming**
shows each token as it arrives, so the user starts reading before the response is
finished. It's worth being precise about what streaming does and doesn't do:

- It does **not** make generation faster — total tokens, total time unchanged.
- It **does** collapse the *felt* wait to TTFT, convert dead waiting into
  productive reading, and enable **early cancellation** (the user sees it going
  the wrong way and stops it).

Streaming is a **presentation-layer** trick, and it's the difference between a
chat product that feels alive and one that feels like submitting a form. Two
metrics describe the felt experience: **TTFT** (the initial wait — optimize this
first) and **TPOT** (time-per-output-token, the streaming *cadence* — it should
read at least as fast as a person reads).

> **Engineering footguns worth knowing** (they silently kill streaming): a
> buffering proxy or response compression can revert a stream to a single batched
> blob; mid-stream errors can't use HTTP status codes (the 200 already went out),
> so you need an in-band error convention; and a prompt-cache hit can skip
> generation entirely, changing the timing profile. The UX promise of streaming
> depends on the plumbing actually streaming end-to-end.

---

## Matching feedback to the length of the wait

The durable rule: **the feedback you show should match how long the user will
wait.**

| Wait | Feedback |
|---|---|
| < 1s | none needed |
| 1–10s | a looped/indeterminate indicator (spinner, animated dots) — an animated progress indicator makes users tolerate *~3× longer* waits with higher satisfaction |
| > 10s | **determinate** progress — for LLMs, the streaming text itself *is* the determinate signal |

Two complementary patterns sharpen the start of the wait:

- **Skeleton screens** beat spinners when content is imminent (they're perceived
  as faster) — but they *imply content is coming*, so they punish you if it
  doesn't arrive. Use them when you're confident a response is on its way.
- **Optimistic UI** — echo the user's own message into the transcript instantly
  and show a "thinking" placeholder *before* the first token. The user gets
  immediate acknowledgment that the system heard them, which buys you the TTFT
  wait for free.

---

## Reasoning models break the 10-second limit on purpose

Reasoning/effort models ([Module 2](../part-02-prompt-engineering/02-prompting-reasoning-models.md),
[Module 7](../part-07-cost-and-latency/04-latency-engineering.md)) can think for
tens of seconds or minutes before the answer begins — far past the 10s attention
limit. The UX response is to **make the long wait legible and continuously
moving**, and to lean on the fact that users *tolerate* long waits when they
expect rigor (code, math, deep research). Patterns that work:

- A **continuously scrolling** view of the reasoning summary or status (the
  "elevator-mirror effect" — motion that signals progress even though you can't
  show a percentage).
- **Status labels** that name the current step ("Searching the codebase…",
  "Running tests…").
- An **elapsed-time counter** — honest, and it reframes the wait as effort.

One important restraint, straight from the research: **more transparency is not
automatically better UX.** Showing the *raw* chain of thought by default
overwhelms — and the reasoning trace can contain "half-baked thoughts" that
mislead. Keep the raw reasoning **collapsed by default**, available on demand for
the users who want to check the work. (This is the [Module 9 cost-knob](../part-09-multimodal/00-multimodal-fundamentals.md)
discussion's UX twin: surface a summary, hide the firehose.)

`★ Insight ─────────────────────────────────────`
- **TTFT, not total time, governs "feel."** Streaming doesn't speed the model up
  — it collapses the perceived wait to the first token and turns waiting into
  reading. It is the highest-leverage AI-UX pattern, and the easiest to break
  with a buffering proxy.
- **Long reasoning waits are tolerable when they're legible and you expected
  rigor** — keep the wait moving with status and an elapsed counter, but collapse
  the raw chain of thought; transparency past a point is noise, not trust.
`─────────────────────────────────────────────────`

## Next

→ [Trust, transparency & citations](02-trust-transparency-and-citations.md) —
making trust *calibrated*.
