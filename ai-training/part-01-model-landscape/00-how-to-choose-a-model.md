---
title: How to choose a model
module: 01 — Model Landscape
lesson: 00
est_time: 35 min reading
last_reviewed: 2026-06-18
tags: [ai, models, decision-framework]
---

# How to choose a model

This is the spine of the module. The catalogs that follow only matter once you can
ask them the right question. **This page ages slowly; the catalogs age fast — learn
this part deeply.**

## The core idea: task × constraints → shortlist

You don't pick a model by "which is best." You pick by intersecting two things:

1. **The task** — what kind of work is this? (coding, extraction, long-doc Q&A,
   reasoning, vision, creative writing…)
2. **The hard constraints** — what's non-negotiable? (budget per call, latency,
   data residency/privacy, must-run-offline, ecosystem you're already in…)

The task tells you *what kind of model*. The constraints usually tell you *which
specific one* — and frequently they're what actually decide it (a privacy
requirement forces local; a cost ceiling forces a small/cheap tier).

## Step 1 — Classify the task

| Task type | What it demands | What to favor |
|---|---|---|
| **General chat / drafting** | Broad competence, good tone | A flagship or mid-tier generalist |
| **Coding (interactive / agentic)** | Strong code + tool use + long context | A coding-specialist or top agentic model |
| **Reasoning / math / planning** | Step-by-step "thinking" | A reasoning model at high effort |
| **Long-document / codebase analysis** | Huge context window | A 1M+ context model |
| **High-volume classification / extraction** | Cheap, fast, "good enough" | The smallest model that passes your eval |
| **Vision / multimodal** | Image (or audio/video) input | A natively multimodal model |
| **Real-time / voice / low-latency** | Speed over peak intelligence | A small "flash/mini/nano" tier |
| **On-device / offline** | Runs without a network | A small local model |
| **Creative / long-form writing** | Voice, coherence, style | A flagship; pick by taste |
| **Search-grounded / fresh facts** | Live retrieval + citations | A search-native model |

> A huge mistake is **over-modeling**: using a frontier reasoning model to tag
> support tickets. Match the model to the *floor* the task needs, then go up only if
> your eval says you must.

## Step 2 — Apply the constraints (this is usually what decides it)

Walk these in order. The first hard "no" eliminates whole categories.

1. **Can the data leave your machine / network?**
   - No → you're in **local / self-hosted** territory. Skip to
     [the local ecosystem](02-open-weight-local-ecosystem.md). Most other choices
     collapse.
   - Yes → continue.
2. **What's the cost ceiling per request / at volume?**
   - Tight + high volume → cheap small tiers (nano/mini/flash/lite) or a cheap
     open-weight model on your own infra. Reasoning models are usually out.
   - Loose / quality-dominated → flagships are on the table.
3. **What's the latency requirement?**
   - Sub-second / interactive voice → small fast tier; avoid reasoning modes.
   - Background / batch → anything; use batch APIs for ~50% off.
4. **Which ecosystem are you already in?**
   - On AWS → Amazon Nova / Bedrock-hosted models integrate cleanly.
   - On Google Cloud → Gemini via Vertex.
   - Heavy tool/SDK needs → the provider with the most mature tooling for your stack.
5. **Do you need a capability only some models have?**
   - 2M+ context, native video, built-in web search, on-device bundling — these
     narrow the field hard. Let the rare capability drive the pick.

After Steps 1–2 you typically have **2–3 candidates**, not twenty.

## Step 3 — The build-vs-buy axis (API vs. local)

This deserves its own decision because it's the biggest fork.

| Reach for an **API (proprietary)** when… | Reach for **local / open-weight** when… |
|---|---|
| You want the highest quality available | Data **cannot** leave your environment |
| Volume is low/moderate (per-token fees are cheaper than running a GPU) | Volume is huge and steady (own-hardware amortizes) |
| You don't want to manage infrastructure | You need full control / customization / fine-tuning |
| You need the newest capabilities first | You need **zero per-token cost** or offline operation |
| You want the most mature tools/SDKs | You want no vendor lock-in / reproducibility |

A common mature pattern is **hybrid**: cheap local model for the 80% easy cases, API
flagship for the 20% hard ones (a "model cascade" / router).

## Step 4 — Validate cheaply before committing

Never commit an architecture to a model on vibes or a leaderboard.

- **Run your own 10–20 example mini-eval** on the shortlist. Leaderboards measure
  *someone else's* tasks; your task is what matters.
- **Start one tier down** from your instinct and see if it passes. You can always go
  up.
- **Measure real cost**, including hidden reasoning tokens (reasoning/"thinking"
  models bill the tokens you can't see, so effective cost runs above the sticker).
- **Re-verify price and limits** on the provider's docs the day you commit.

## The decision matrix (task → first picks)

Concrete starting points as of **June 2026**. These name specific models — they
*will* go stale; the method above won't. Verify in the catalogs:
[frontier/proprietary](01-frontier-proprietary-models.md),
[local](03-top-100-local-models.md).

| Task | Proprietary first pick(s) | Open-weight / local first pick(s) |
|---|---|---|
| **General / default** | Claude (Opus/Sonnet), GPT-5.5, Gemini 3.1 Pro | Qwen3 (8–32B), gpt-oss-120b, Llama 3.3-70B |
| **Coding — agentic** | Claude (Opus, high effort), GPT-5.x-Codex, Gemini 3.5 Flash | Qwen3-Coder, Kimi K2.6, GLM-4.7-Flash (local), Devstral 2 |
| **Coding — IDE autocomplete (FIM)** | Codestral | Qwen2.5-Coder (7–32B), Codestral, StarCoder2 |
| **Reasoning / math** | Claude (max effort), GPT-5.5 Pro / o3-pro, DeepSeek V4-Pro | DeepSeek-R1 (+ distills), QwQ-32B, Phi-4-Reasoning |
| **Long-context (docs / code)** | Gemini 3.1 Pro (2M), Claude (1M) | Llama 4 Scout (10M), MiniMax-01 (4M), DeepSeek V4 (1M) |
| **Cheap high-volume extraction** | Nova Micro/Lite, GPT-4.1/5.4 nano, Gemini Flash-Lite, Claude Haiku | Qwen3-4B, Gemma 4 small, Phi-4-mini |
| **Multimodal / vision** | Gemini 3.1 Pro (video/audio), Claude, GPT-5.5, Nova Premier | Qwen3-VL, InternVL3, Pixtral, Llama 4 |
| **Real-time / low-latency** | Gemini Flash/Flash-Lite, Claude Haiku, GPT-5.4 mini, Nova Lite | Qwen3-4B, Gemma 4 E4B, LFM2.5 |
| **On-device / offline** | Gemini Nano (Android/Chrome) | Qwen3-0.6–4B, Gemma 4 E2B/E4B, Phi-4-mini, Llama 3.2 1–3B |
| **Search-grounded / fresh facts** | Perplexity Sonar, Grok 4.x | *(needs your own retrieval stack — see future RAG module)* |
| **Privacy / on-prem / fine-tune** | *(API can't satisfy hard privacy)* | Qwen3, Gemma, DeepSeek, Mistral (Apache/MIT) |

## Common anti-patterns

- **Leaderboard chasing** — top of a benchmark ≠ best for *your* task.
- **Over-modeling** — frontier reasoning model for a job a 4B model nails.
- **Ignoring hidden reasoning-token cost** — your bill is 2–5× the sticker.
- **Choosing local "for cost" at low volume** — a part-time GPU is often pricier than
  pennies-per-call API usage; local wins at scale or for privacy, not by default.
- **Skipping the license check** on an open-weight model you intend to ship
  commercially.

---

## Next

→ [Frontier & Proprietary Models](01-frontier-proprietary-models.md) ·
→ [The Open-Weight / Local Ecosystem](02-open-weight-local-ecosystem.md)
