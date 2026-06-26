---
title: Local & on-device multimodal
module: 09 — Multimodal & Generative Media
lesson: 04
est_time: 35 min reading
last_reviewed: 2026-06-26
tags: [ai, local, apple-silicon, mlx, vision, whisper, diffusion]
---

# Local & on-device multimodal

Everything in lessons 01–03 has a local counterpart: you can run vision models,
speech recognition, text-to-speech, and image generation **entirely on your own
machine** — no API key, no per-token bill, no data leaving the device. This
lesson is the multimodal extension of **[Module 8 — Local Inference](../part-08-local-inference/00-why-and-the-local-stack.md)**,
and like that module it is **Apple-Silicon-weighted**, because unified memory
makes a Mac a genuinely capable multimodal box.

> ⚠️ **Dated snapshot — June 2026.** Local model names and tool versions move
> fast. The framework — what fits in unified memory, which engine to use — is
> the durable part.

---

## The durable framework: what's realistic locally on a Mac

The same engine/front-end/server mental model from
[Module 8, lesson 00](../part-08-local-inference/00-why-and-the-local-stack.md)
applies — llama.cpp / MLX are the engines, Ollama / LM Studio bundle them. The
new question is **what fits**, and on Apple Silicon that's governed by
**unified memory** (the GPU and CPU share one pool; weights live once, no
copy). Practical dividing lines, ~70% of RAM usable after the OS:

| RAM | Realistically local |
|---|---|
| **8 GB** | small VLMs (≤4B), local ASR (whisper.cpp), SD 1.5 — tight |
| **16 GB** | **the serious floor** — SDXL + ≤8B vision model + ASR/TTS together; FLUX only at Q4 |
| **32 GB** | comfortable — 24–32B VLMs, FLUX/FLUX.2 at Q8 |
| **64 GB+** | approaches a small workstation — full-precision FLUX, 24–32B VLMs with headroom |

The rule: **small/mid vision models, all local ASR, small TTS, and SDXL image
generation run well on a 16–32GB Mac.** What pushes you to a discrete GPU or
cloud is *throughput and concurrency* (serving many streams) and the largest
models (72B+ VLMs, full-precision video) — not usually fitting a single model.

---

## Local vision-language models (VLMs)

| Model | Sizes | Notes |
|---|---|---|
| **Qwen3-VL** | 2–32B dense; 30B/235B MoE | current Qwen flagship, 256K context, strong grounding |
| **Qwen2.5-VL** | 3–72B (Apache-2.0) | the most common local GGUF/MLX default |
| **Gemma 3 vision** | 4/12/27B | very popular, broad runtime support |
| **Mistral Small 3.1/3.2** | 24B | folds in the Pixtral encoder (Pixtral 12B is now deprecated) |
| **Moondream 2 / 3** | 2B (M3: 9B MoE, ~2B active) | edge-focused; 4-bit ~2.45GB |
| **SmolVLM** | 256M / 500M / 2.2B | smallest; phone / base-Mac class; MLX day-zero |

**How to run them** (the multimodal extension of Module 8's tools):

- **llama.cpp** — multimodal via `libmtmd`: a core LLM GGUF **plus** a separate
  `mmproj` projector GGUF. `llama-server -m model.gguf --mmproj mmproj.gguf`.
- **Ollama** — built-in vision: `ollama run qwen2.5-vl:7b`, `gemma3:12b`,
  `llama3.2-vision`.
- **LM Studio** — GGUF (llama.cpp) **plus an Apple MLX backend**; the MLX vision
  builds are generally faster on Apple Silicon.
- **MLX-VLM** (`Blaizzy/mlx-vlm`) — the native Mac path; inference + LoRA
  fine-tune; new VLMs land in `mlx-community` fastest.

---

## Local audio on Apple Silicon

**ASR.** Two paths for the same Whisper weights:
- **whisper.cpp** (Metal + Core ML on the ANE) — most portable/embeddable;
  models tiny → large-v3 + the **large-v3-turbo** sweet spot.
- **MLX-Whisper** — ~2× faster than whisper.cpp on large-v3-turbo on
  M-series; the fastest mainstream Apple-Silicon path. This is the engine
  behind the repo's [`transcribe/`](../../transcribe/) tool (see
  [Module 8, lesson 02](../part-08-local-inference/02-apple-silicon-and-mlx.md)).

**Local TTS:**
| Model | Size | Notes |
|---|---|---|
| **Kokoro-82M** | 82M, Apache-2.0 | **default rec** — 54 voices, sub-0.3s synth, best quality/size/license balance; runs via MLX |
| **Piper** | tiny VITS, MIT | fastest/lightest on CPU; more robotic |
| **Sesame CSM-1b** | 1B, Apache-2.0 | highest naturalness in open TTS; heavier; MLX via `csm-mlx` |

`Blaizzy/mlx-audio` bundles Kokoro / CSM / Whisper with 3–8-bit quant — the
single best entry point for an Apple-Silicon audio stack.

---

## Local image generation on Apple Silicon

What runs: SD 1.5 / SDXL (mature, light), SD3.5, **FLUX.1** (12B, needs
quantization), and **FLUX.2 klein** (4B, Apache-2.0, ~7.75GB). Tooling:

- **Draw Things** — native free Mac/iOS app, Metal, no Python. **Most-recommended
  for most users**; supports FLUX.2 Klein + SD3.5.
- **mflux** — native **MLX** CLI with built-in 4/8-bit quant and `--low-ram`;
  the best native command-line path (FLUX.1/.2, Qwen Image).
- **ComfyUI** — full node-based SD/FLUX workflows on macOS.
- **apple/ml-stable-diffusion** — Core ML, for native Swift apps.

Feasibility tracks the unified-memory table above: **16GB** does SDXL smoothly
and FLUX only at Q4; **32GB** runs FLUX/FLUX.2 at Q8 (near-invisible quality
loss); **64GB** fits full bf16 FLUX (~23.8GB). A caveat worth knowing: **Core ML
is not reliably faster than the Metal default** for diffusion — Draw Things and
mflux are the practical fast paths.

---

## Why local multimodal matters

The case is the same as Module 8's, sharpened by the data sensitivity of media:

- **Privacy** — medical images, ID documents, private photos, recorded calls
  never leave the device. For a lot of multimodal data this isn't a preference,
  it's a requirement.
- **Cost at volume** — OCR-ing 100k scanned pages or transcribing thousands of
  hours of audio is brutal on a per-call API; a local model amortizes to ~free.
- **Offline & latency** — no network round-trip; works on a plane.

And the same **OpenAI-compatible `base_url` unlock** from
[Module 8, lesson 05](../part-08-local-inference/05-integration-and-operations.md)
applies: a local VLM served on `localhost` speaks the OpenAI vision API, so the
RAG (Module 3) and agent (Module 4) patterns run fully offline against your own
multimodal models.

`★ Insight ─────────────────────────────────────`
- **Unified memory is the enabler.** Because weights live once and the GPU reads
  them with no copy, a 16–32GB Mac runs a genuinely useful multimodal stack —
  vision + ASR + TTS + SDXL — that would need a discrete GPU on other platforms.
- **Local multimodal is most compelling exactly where the data is most
  sensitive** — faces, IDs, medical scans, recorded calls. The privacy argument
  that's merely *nice* for text is often *mandatory* for media.
`─────────────────────────────────────────────────`

## Next

→ [Putting it together](05-putting-it-together.md) — a multimodal pipeline
capstone and the cost/latency picture at scale.
