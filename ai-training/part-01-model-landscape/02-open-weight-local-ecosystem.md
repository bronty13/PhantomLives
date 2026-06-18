---
title: The open-weight / local ecosystem
module: 01 — Model Landscape
lesson: 02
est_time: 35 min reading
last_reviewed: 2026-06-18
tags: [ai, models, open-weight, local, quantization, hardware]
---

# The open-weight / local ecosystem

This page is the **framework** for running models on your own hardware: what the
formats mean, what your machine can actually run, which tool to use, and the
licensing traps. The model list itself is the next page —
[Top ~100 Local Models](03-top-100-local-models.md).

> ⚠️ **Dated snapshot — June 2026.** Specific model names move fast; the *rules of
> thumb* (memory math, format choices, hardware tiers) age slowly. Learn the rules.

## Why run locally at all?

Three real reasons (and one bad one):

1. **Privacy / data residency** — the data physically cannot leave your machine. This
   is the strongest reason and often the *only* one that matters.
2. **Cost at scale** — huge, steady volume amortizes hardware below per-token API
   fees.
3. **Control** — fine-tuning, reproducibility, offline operation, no vendor lock-in.

The bad reason: *"to save money"* at low volume. A part-time GPU (electricity +
hardware amortization) frequently costs more than pennies-per-call API usage. Local
wins on **privacy and scale**, not by default.

## Licensing — read this before you ship (the #1 trap)

"Open-weight" does **not** mean "do whatever you want." The ecosystem splits into:

- **Truly open (Apache 2.0 / MIT)** — commercial use, fine-tuning, redistribution all
  fine. Safe default for commercial work: **Qwen, Gemma, DeepSeek, GLM, Mistral
  (most), Phi, Granite, OLMo, SmolLM, gpt-oss, Nemotron.**
- **Restricted "community" licenses** — free to run, but with strings (user caps,
  revenue triggers, no-train-on-outputs clauses, or non-commercial):
  - **Llama 4** — Llama Community License (acceptable-use + >700M-MAU clause).
  - **Cohere Command / Aya** — CC-BY-NC (**non-commercial**; commercial needs a paid
    license).
  - **Grok 2.5** — revocable, prohibits training on outputs.
  - **Flux.1 Dev**, some media models — non-commercial only.

**Rule:** for commercial shipping, default to Apache 2.0 / MIT families. Read the
actual license for anything Llama-, Cohere-, Grok-, or Flux-Dev-based.

## Quantization — what the formats mean

Quantization compresses weights to fewer bits so models fit in less memory and run
faster, at a small quality cost. **`Q4` (4-bit) is the universal sweet spot — ~95% of
full quality at ~¼ the size.**

| Format | Runs on | Notes |
|---|---|---|
| **GGUF** | llama.cpp, Ollama, LM Studio | The de-facto **local** format. CPU+GPU hybrid offload, runs everywhere. `Q4_K_M` is the default; step up to `Q5_K_M`/`Q6_K`/`Q8_0` if you have headroom. |
| **MLX** | Apple MLX, LM Studio (Mac) | **Apple-Silicon-native**; uses unified memory, generally faster than GGUF on M-series Macs. The right choice on a Mac. |
| **GPTQ** | vLLM, text-generation-webui | GPU-only post-training quant; good serving throughput. |
| **AWQ** | vLLM, TGI | Activation-aware 4-bit; strong quality/throughput for multi-user serving. |
| **FP8 / NVFP4 / MXFP4** | vLLM, TensorRT-LLM, modern GPUs | Newer low-bit float formats. NVFP4 needs Blackwell-class NVIDIA GPUs; MXFP4 is used by gpt-oss and DeepSeek V4. Many 2026 flagships ship *natively* in FP8/INT4. |

## Hardware sizing — the memory math

**Rule of thumb: ~2 GB of VRAM/RAM per 1B parameters at FP16, ~0.5 GB per 1B at
4-bit**, plus ~15–20% for the KV cache and overhead. Long context inflates the KV-
cache part substantially.

| Model class | 4-bit footprint | What runs it |
|---|---|---|
| **0.5–4B** (on-device) | 0.5–3 GB | Any laptop, phone, Pi, 8 GB Mac, CPU-only |
| **7–9B** | ~5–6 GB | 8 GB GPU (tight) / 12 GB comfortable / 16 GB Mac |
| **13–15B** | ~8–10 GB | 12–16 GB GPU, 16–24 GB Mac |
| **27–35B dense** | ~18–24 GB | RTX 4090 (24 GB), 32–48 GB Mac |
| **70B dense** | ~40–42 GB | 48 GB GPU / 2× 24 GB / 64 GB Mac |
| **MoE (e.g. 35B-A3B)** | full **total** must fit (~18–24 GB) but runs at **active**-param speed (~3B) | 32–48 GB Mac or a 24 GB GPU |
| **Frontier MoE (DeepSeek V4, Kimi K2.6, GLM-5.x; 400B–1.6T total)** | 200–600 GB+ even at 2–4 bit | Multi-GPU rigs, 256–512 GB Mac Studio, or just use the API |

> ⚠️ **The MoE gotcha:** a "35B-A3B" needs RAM for **35B**, not 3B. MoE buys you
> *speed*, not *memory savings* — all experts must be resident.

## Runtimes & tools — which to use

- **Ollama** — easiest on-ramp; `ollama run qwen3`. Best default for individuals;
  built on llama.cpp; pulls GGUF.
- **LM Studio** — polished GUI (Mac/Win/Linux), model catalog, OpenAI-compatible
  local server; supports **GGUF and MLX** on Mac.
- **MLX / mlx-lm** (Apple) — native Apple-Silicon framework; **fastest path on
  M-series Macs**; pairs with LM Studio. *(This repo's `transcribe/` already uses MLX
  for Apple Silicon whisper — same family of tooling.)*
- **llama.cpp** — the engine under most of the above; maximal hardware reach (CPU,
  Metal, CUDA, Vulkan, ROCm), GGUF, fill-in-the-middle, grammars. For power users.
- **vLLM** — production **serving** (PagedAttention, high throughput, multi-user);
  GPU-only; loves GPTQ/AWQ/FP8. Use when you're hosting an endpoint.
- **text-generation-webui ("oobabooga")** — Gradio UI; GGUF/GPTQ/AWQ/ExLlama; popular
  for experimentation and roleplay.
- Also common in 2026: **TensorRT-LLM** (max NVIDIA perf), **SGLang** (fast serving,
  strong for agentic/structured output), **llamafile** (single-file portable).

**Quick guidance:** Mac user → **Ollama or LM Studio (MLX)**. NVIDIA single user →
Ollama/LM Studio. Serving many users → **vLLM**.

## How to pick a local model by hardware × task

| You have… | General chat | Coding | Reasoning |
|---|---|---|---|
| **8 GB laptop / phone** | Gemma 4 E2B/E4B, Qwen3-4B, Phi-4-mini | Qwen2.5-Coder-3B | Qwen3-4B-Thinking |
| **16 GB Mac / 8–12 GB GPU** | Qwen3-8B, Gemma 4 12B, Llama-3.1-8B | Qwen2.5-Coder-7B, Codestral | Qwen3-8B, Phi-4-Reasoning |
| **24–32 GB (RTX 4090 / 32 GB Mac)** | Qwen3.6-35B-A3B, GLM-4.7-Flash | Devstral Small 2 (24B), Qwen3-Coder-30B | QwQ-32B, OLMo 3.1-Think-32B |
| **48–128 GB Mac / multi-GPU** | gpt-oss-120b, Nemotron 3 Super | Qwen3-Coder (large), Devstral 2 | gpt-oss-120b, DeepSeek-R1 distills |
| **Workstation cluster / 256 GB+** | DeepSeek V4, Kimi K2.6, GLM-5.2 | Kimi K2.6, DeepSeek V4-Pro | DeepSeek-R1, DeepSeek V4-Pro |

## The defining trend of mid-2026: small-active-param MoE

The biggest shift in local models is **30–35B-total / ~3B-active MoE** (Qwen3.x-A3B,
GLM-4.7-Flash, LFM2.5, Nemotron Nano). They give **near-mid-range quality at near-tiny
speed** — *if* you have RAM for the full weight set. If you have 32+ GB, this class is
usually the best quality-per-speed you can run.

## Practical starting recipe (Apple Silicon, this repo's primary platform)

1. Install **Ollama** (`brew install ollama`) or **LM Studio**.
2. Start with **Qwen3-8B** (general) or **Qwen2.5-Coder-7B** (coding) at `Q4_K_M` /
   4-bit MLX — comfortable on a 16 GB Mac.
3. If you have 32 GB+, jump to a **35B-A3B MoE** for a big quality bump at similar
   speed.
4. For embeddings/RAG, add **Qwen3-Embedding-0.6B** or **nomic-embed-text**.

---

## How to re-verify this page

The memory math and format table are stable. The model names in the picker tables
will drift — cross-check against the next page
([Top ~100 Local Models](03-top-100-local-models.md)) and Hugging Face Hub
trending/downloads when refreshing, then bump `last_reviewed`.

## Next

→ [Top ~100 Local Models](03-top-100-local-models.md)
