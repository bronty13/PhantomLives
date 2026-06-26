---
title: Multimodal fundamentals
module: 09 — Multimodal & Generative Media
lesson: 00
est_time: 30 min reading
last_reviewed: 2026-06-26
tags: [ai, multimodal, vision, audio, generation, fundamentals]
---

# Multimodal fundamentals

Everything in Modules 1–8 quietly assumed one shape: **text in, text out**. A
chat completion takes a string (maybe with some tool results) and returns a
string. That covers an enormous amount of useful work — but it is a slice of
what current models can do. This module is about the rest of the slice:
**images, audio, video, and the generation of media**, not just its consumption.

Like every module here, it leads with the durable mental model — *what problem
shape am I in, and when is text-only still the right call?* — and treats the
specific models and prices as dated snapshots you re-verify.

> ⚠️ **Dated snapshot — June 2026.** Every model name and price in this module
> is a point-in-time fact in a market that ships monthly. Lead with the
> framework; re-verify the catalogs against the provider links before you
> commit.

---

## The modality matrix

The first question for any multimodal task is mechanical: **which modalities go
in, and which come out?** Lay it on a grid:

| | **Text out** | **Image out** | **Audio out** | **Video out** |
|---|---|---|---|---|
| **Text in** | chat (Modules 1–8) | text-to-image | text-to-speech | text-to-video |
| **Image in** | vision / VQA / OCR | image editing, inpainting | (rare) | image-to-video |
| **Audio in** | speech-to-text (ASR) | — | speech-to-speech | — |
| **Video in** | video understanding | — | — | video-to-video edit |

Two things fall out of this grid immediately:

1. **No single model fills the whole grid.** A frontier "multimodal" LLM
   (Gemini, GPT-5.x, Claude) typically occupies the **left column** —
   *understanding* many input modalities, emitting text. *Generating* image,
   audio, or video is a different class of model (FLUX, Veo, ElevenLabs) with
   its own API, pricing, and failure modes. Treating "multimodal" as one
   capability is the most common beginner mistake.
2. **The diagonal is where the action is.** Cross-modal cells —
   image→text (OCR), text→image (generation), audio→audio (voice agents) — are
   where the genuinely new product surface lives.

This module walks the grid: **vision & documents** (lesson 01, image→text),
**audio & voice** (lesson 02, audio↔audio), **image & video generation**
(lesson 03, text→pixels), **local multimodal** (lesson 04, all of it on your
own hardware), and a **capstone pipeline** (lesson 05) that chains several
cells together.

---

## Native-multimodal vs. pipeline-of-specialists

There are two architectures for any multimodal task, and choosing between them
is the central design decision:

- **Native multimodal** — one model ingests (or emits) multiple modalities
  directly. Gemini takes video natively; a speech-to-speech model hears and
  speaks in one pass. Fewer hops, lower latency, preserves cross-modal nuance
  (tone, layout, timing). Costs more per call and gives you fewer knobs.
- **Pipeline of specialists** — chain single-purpose models. Transcribe audio
  with a dedicated ASR model → reason over the text with a cheap LLM →
  synthesize a reply with a TTS model. Each stage is swappable and individually
  cheap, you can log/guardrail the text in the middle, but latency *stacks*
  across hops and you lose paralinguistic signal (the LLM never hears the
  caller's frustration).

This is the same **build-it-from-parts vs. buy-the-integrated-thing** tension
you saw in Module 4 (agent vs. workflow) and Module 7 (build vs. buy). The
durable rule: **start with the pipeline of specialists** — it is cheaper,
debuggable, and each part is replaceable — and reach for native multimodal only
when latency or fidelity (a live voice agent, video understanding) actually
demands it.

---

## The token cost of pixels and seconds

The single most important *durable* fact about multimodal: **non-text inputs are
converted to tokens and billed at the input-token rate.** There is rarely a
separate "vision surcharge" — an image simply *becomes* N input tokens.

- **Images → tokens scale with resolution/area.** Tile-based schemes
  (`base + tiles × per_tile`) and patch-based schemes (`⌈w/32⌉ × ⌈h/32⌉`
  patches) both share one rule: more pixels = more tokens, up to a per-model
  cap. A 2048² image costs roughly 4× a 1024² one for no accuracy gain on most
  tasks. **Downscale to the smallest resolution that still resolves the detail
  you need** (usually <1500px long edge for documents/UI).
- **Audio → tokens scale with duration.** Roughly ~1 token per 100ms of input
  speech (~600 tok/min) on realtime APIs; output audio is pricier still.
- **Video → tokens scale with frames × resolution × length.** The most
  expensive modality by far.

This connects Module 9 straight back to **[Module 7 — Cost & Latency](../part-07-cost-and-latency/01-token-economics.md)**:
resolution and clip-length are the master cost knobs of multimodal, exactly as
context length is the master knob of text.

---

## When text-only is still the right call

Multimodal is seductive — but the discipline of **[Module 4's "when not to build
an agent" gate](../part-04-agents-and-tool-use/00-agent-fundamentals.md)**
applies here too. Before reaching for a vision or audio model, ask:

- **Is the information already available as text?** A PDF with a real text layer
  doesn't need a vision model — extract the text and use a normal LLM call, far
  cheaper and more reliable. Reach for vision-OCR only when the document is
  *scanned* (image-only) or layout-critical.
- **Would a deterministic tool do it better?** Barcode scanning, EXIF reading,
  audio loudness measurement — don't pay a model to do what a library does
  exactly and for free.
- **Does the modality carry signal you'll actually use?** Sending full-color
  4K photos to extract a serial number wastes tokens; a downscaled grayscale
  crop is cheaper and just as accurate.

`★ Insight ─────────────────────────────────────`
- **"Multimodal" is a grid, not a feature.** The product question is always
  *which cell* — and the most useful cells (OCR, generation, voice) each need
  a different model class, not a bigger version of your chat model.
- **The pixel/second-to-token conversion is the through-line** of this whole
  module. Every cost, latency, and quality tradeoff downstream traces back to
  how much you're tokenizing — which you control with resolution, duration,
  and whether you needed the modality at all.
`─────────────────────────────────────────────────`

## Next

→ [Vision & document understanding](01-vision-and-documents.md) — the
image→text cell, including the Claude lineup's exact modality + pricing picture.
