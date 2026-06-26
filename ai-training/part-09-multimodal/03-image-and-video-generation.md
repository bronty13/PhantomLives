---
title: Image & video generation
module: 09 — Multimodal & Generative Media
lesson: 03
est_time: 40 min reading
last_reviewed: 2026-06-26
tags: [ai, image-generation, video-generation, diffusion, provenance]
---

# Image & video generation

This is the **text/image → pixels** cell of the [modality matrix](00-multimodal-fundamentals.md):
generating images and video rather than understanding them. It is a different
class of model from the LLMs of Modules 1–8 — diffusion and related
architectures — with its own pricing shapes, control features, and a uniquely
thorny licensing/provenance picture.

> ⚠️ **Dated snapshot — June 2026.** This is the fastest-rotting catalog in the
> course — note the cluster of imminent shutdowns flagged below. Lead with the
> durable framework; re-verify everything at the provider links.

---

## Durable framework #1 — know which billing model you're in

A "per-image price" is only comparable when two providers both bill per image at
the same quality/resolution. They often don't. The five shapes:

| Billing model | Billed on | Examples | Gotcha |
|---|---|---|---|
| **Per-image (flat)** | fixed $/image by quality/res | Imagen, Ideogram, Stability | edits often priced separately |
| **Per-token** | input + output, image = N tokens | OpenAI gpt-image, Google Nano Banana | per-image figure is *derived*; refs + res inflate it |
| **Per-megapixel** | first MP flat, each added MP incremental | FLUX.2 | resolution directly drives cost |
| **Compute-credits** | buy a balance, each op debits | Stability, Firefly, Midjourney | pin the credit→$ rate |
| **Subscription** | flat monthly, rate-limited | Midjourney, Firefly | not metered per image |

The durable skill: **identify the billing shape before comparing prices**, and
for per-token / per-megapixel models, derive the per-image cost at *your*
resolution and reference-image count, not the headline number.

## Durable framework #2 — the control features

Generation quality is table stakes now; **control** is where products differ:

- **Inpainting** — regenerate a masked region.
- **Outpainting / expand** — extend the canvas beyond the original frame.
- **Reference / style images** — condition on an example.
- **Instruction editing** — edit the whole image by a text command ("make it
  night"). This is the headline 2025–26 capability (the "Kontext / Nano Banana"
  paradigm) and the main reason to pick one model over another.
- **Character consistency** — keep the same person/object across generations.

## Durable framework #3 — the licensing axes (commercial-use checklist)

This trips up every commercial project. Four independent questions:

1. **Output ownership** — most API providers assign output to you, but under
   current US law (the *Thaler* line, reaffirmed by the Copyright Office) purely
   AI-generated content may not be **copyrightable** at all. "You own it" really
   means "the provider doesn't claim it."
2. **Commercial-use right** — does your plan tier permit it? Is there a revenue
   cap (e.g. Stability's Community License is free commercial only **under $1M
   revenue**; Midjourney requires Pro/Mega above $1M)?
3. **Model-weights license** (open-weight only) — can you *self-host
   commercially*? FLUX `[dev]` weights are non-commercial even though the
   outputs are usable.
4. **Training-data provenance & indemnification** — the Adobe Firefly / Bria
   differentiator: models trained only on licensed data, with IP indemnity.

---

## Snapshot — image generation (June 2026)

| Provider / Model | Status | Pricing | Control | Licensing note |
|---|---|---|---|---|
| **OpenAI gpt-image-2** | GA | per-token; ≈ $0.006–0.211/image @1024² by quality | edits, masks, multi-ref | user owns output; C2PA + SynthID on outputs |
| **Google Nano Banana** (`gemini-2.5-flash-image`) | GA | ~$0.039/image | conversational multi-turn editing | SynthID + C2PA |
| **Google Nano Banana Pro** (`gemini-3-pro-image`) | GA | ~$0.134 (1K/2K), $0.24 (4K) | char consistency (≤5 refs), fusion, Search grounding | SynthID + C2PA |
| **Google Imagen 4** | ⚠️ **DEPRECATED — shutdown 2026-08-17** | $0.02–0.06/image | no inpaint/edit | migrate to Nano Banana |
| **Black Forest Labs FLUX.2** | GA (flagship) | per-megapixel, ~$0.014–0.07/MP | ≤10 refs, strong typography/UI | klein-4B Apache-2.0; `[dev]` non-commercial weights |
| **Stability (Image Ultra/Core, SD 3.5)** | GA | credits, ~$0.03–0.08/image; edits $0.05 | inpaint, erase, search-replace, upscale | Community License: free commercial **under $1M rev** |
| **Ideogram 4.0** | GA | $0.03–0.10/image | best-in-class **text rendering**, Magic Fill | commercial on paid plans |
| **Adobe Firefly Image 4** | GA | plan-based | Generative Fill/Expand, structure/style ref | **commercially-safe + enterprise IP indemnity** (Adobe models only) |
| **Midjourney V8.1** | GA | subscription ($10–120/mo) | Vary Region, Omni-Reference | **no official public API** (any "MJ API" is third-party) |

Three "the conventional wisdom is stale" corrections worth flagging to a reader:
**(1)** Google's image play is now **Nano Banana**, not Imagen (deprecated).
**(2)** BFL's flagship is **FLUX.2 (per-megapixel)**, not FLUX.1/Kontext.
**(3)** **Midjourney still has no official public API.**

---

## Snapshot — video generation (June 2026)

Video adds axes images don't have. The durable ones:

- **Mode:** text-to-video, image-to-video (a still becomes the first frame — the
  production workhorse), and **video-to-video edit** (the 2025–26 frontier:
  Runway Aleph, Sora edits).
- **Duration is the binding constraint.** ~5–10s per generation is the norm
  (8s modal); "extend/continue" stitches to ~30–120s. Coherent single-pass
  beyond ~30s is unsolved — everyone chains clips.
- **Native synced audio** is the 2025 dividing line. Audio-native: Veo 3.1,
  Sora 2, Kling 3.0, LTX-2. Silent: Luma Ray, most open-weight models.
- **Pricing is per-second.** ~$0.05/s (cheap) → $0.10–0.40/s (flagship 720–1080p)
  → $0.50–1.50/s (4K). A 10s flagship clip ≈ $1–4.

| Provider / Flagship | Native audio | Max res | Public API? |
|---|---|---|---|
| **Google Veo 3.1** | ✅ dialogue + sfx | 720/1080p/4K | ✅ (current safe default) |
| **OpenAI Sora 2 / 2 Pro** | ✅ synced | 720p / 1080p (Pro) | ⚠️ **API retires 2026-09-24** |
| **Runway Gen-4.5 + Aleph 2.0** | mostly silent | ~720p | ✅ (editing specialist) |
| **Kling 3.0** (Kuaishou) | ✅ multilingual | 1080p | ✅ (strongest non-Western) |
| **Luma Ray3.14** | ❌ | 1080p (4K upscale) | ✅ |

**Open-weight video** (self-host — almost entirely Chinese labs + Lightricks):
Alibaba **Wan 2.2** (Apache-2.0, runs on a single consumer GPU), Tencent
**HunyuanVideo-1.5**, Lightricks **LTX-2** (native 4K, synced audio). See
[lesson 04](04-local-and-on-device.md) for what's realistic locally.

> ⚠️ **Near-term shutdowns** (within ~3 months of this snapshot): Veo 3 / Veo 2
> (2026-06-30), Imagen 4 (2026-08-17), Amazon Nova Premier (2026-09-14), the
> Sora API (2026-09-24). A catalog this volatile is exactly why the course
> teaches the framework first.

---

## Provenance & watermarking

Increasingly a *requirement*, not a nicety. Two **complementary** technologies —
OpenAI and Google ship both at once:

| | **C2PA Content Credentials** | **Google SynthID** |
|---|---|---|
| Type | open standard; signed metadata **manifest** | proprietary **in-pixel invisible watermark** |
| Survives edits? | tamper-**evident** but **strippable** (a screenshot removes it) | survives crop/filter/compression |
| Who can detect | anyone, openly | mostly Google-only |

They pair because each covers the other's weakness: C2PA travels with the file
as auditable metadata but a screenshot strips it; SynthID survives the
screenshot but only Google can reliably read it.

**Regulatory accelerant:** the **EU AI Act Article 50** (AI outputs must be
machine-readable and detectable) **applies 2026-08-02** — weeks after this
snapshot. If you generate media for an EU audience, provenance is becoming a
compliance obligation, not a feature. (Governance is a candidate future module;
this is the concrete near-term hook.)

`★ Insight ─────────────────────────────────────`
- **Generation models are a different animal from LLMs.** The hard parts aren't
  prompting — they're knowing your *billing shape*, your *control features*, and
  the *four-axis licensing* picture before you ship anything commercial.
- **Provenance is going from optional to mandatory.** C2PA + SynthID together,
  plus the EU AI Act Art. 50 deadline, mean "did a machine make this, and can
  you prove it" is now a product requirement for generated media.
`─────────────────────────────────────────────────`

## Next

→ [Local & on-device multimodal](04-local-and-on-device.md) — running vision,
audio, and image generation on your own (Apple Silicon) hardware.
