---
title: Why local, and the local-inference stack
module: 08 — Local Inference Deep Dive
lesson: 00
est_time: 25 min reading
last_reviewed: 2026-06-18
tags: [ai, local-inference, ollama, mlx, llama-cpp, vllm]
---

# Why local, and the local-inference stack

[Module 1, lesson 02](../part-01-model-landscape/02-open-weight-local-ecosystem.md) mapped
the open-weight *ecosystem*; this module is the **hands-on** version — actually running
models on your own hardware, end to end. It's also the practical "how" behind
[Module 7's self-hosting economics](../part-07-cost-and-latency/05-production-economics-and-build-vs-buy.md).

## Why run locally (the recap)

Three real reasons (from [Module 1](../part-01-model-landscape/02-open-weight-local-ecosystem.md)):
**privacy** (data never leaves the machine — the strongest reason), **cost at scale**
(amortize hardware against steady volume), and **control/offline** (no vendor, no network,
full customization). The bad reason is "to save money" at low volume — a part-time GPU often
costs more than pennies-per-call API usage.

## The mental model: one stack, not five tools

The tools people confuse are mostly **layers of the same stack**. Get this and the rest of
the module is easy:

```
        FRONT-ENDS / SERVERS          ENGINES
        ───────────────────          ───────
        Ollama        ─┐
        LM Studio     ─┼──bundle──►   llama.cpp   (cross-platform: Metal/CUDA/Vulkan/CPU)
        (raw) llama.cpp ┘
        LM Studio     ─────also───►   MLX         (Apple Silicon only — Apple's engine)
        vLLM / SGLang / TGI ───────►  (their own CUDA serving engines, Linux+GPU)
```

- **llama.cpp** is the inference *engine* — and it's what **Ollama** and **LM Studio** run
  under the hood ([lesson 03](03-llama-cpp-and-gguf.md)).
- **Ollama** (CLI-first) and **LM Studio** (GUI-first) are easy *front-ends* over it
  ([lesson 01](01-ollama-and-lm-studio.md)).
- **MLX** is Apple's *separate* engine for Apple Silicon — faster than llama.cpp on
  M-series; LM Studio can use it too ([lesson 02](02-apple-silicon-and-mlx.md)).
- **vLLM** (and SGLang/TGI/TensorRT-LLM) are *production servers* for many concurrent users
  on a GPU box ([lesson 04](04-serving-at-scale-vllm.md)).

So you pick a **front-end** (Ollama / LM Studio / raw llama.cpp / mlx-lm / vLLM), and on a
Mac you also pick an **engine** (llama.cpp-Metal vs MLX).

## Hardware reality check

What you can run is set by memory ([Module 1's sizing table](../part-01-model-landscape/02-open-weight-local-ecosystem.md)):

- **Apple Silicon — unified memory.** CPU and GPU share *one* RAM pool, so usable "VRAM" is
  *most of system RAM*. A 64 GB Mac can load a 70B model at 4-bit; a 24 GB discrete GPU
  cannot. This is why Macs punnch above their weight for local LLMs ([lesson 02](02-apple-silicon-and-mlx.md)).
- **NVIDIA — dedicated VRAM.** Higher bandwidth, but a hard cap (e.g. 24 GB on a 4090) — the
  model + KV cache must fit, or you offload layers to CPU and slow down.

Rough fit at 4-bit (full table in [Module 1](../part-01-model-landscape/02-open-weight-local-ecosystem.md)):
8 GB → 3–4B · 16 GB → 7–8B · 24 GB → 13–14B · 32 GB → a 30B MoE (the 2026 sweet spot) ·
64 GB → 70B · 128 GB → 70B at higher precision or a large MoE. **Context/KV cache eats extra
on top** ([lesson 03](03-llama-cpp-and-gguf.md)) — these are ceilings, not guarantees.

## What this module builds

| Lesson | You'll be able to… |
|---|---|
| [01 Ollama & LM Studio](01-ollama-and-lm-studio.md) | Run your first local model in minutes and hit it from code |
| [02 Apple Silicon & MLX](02-apple-silicon-and-mlx.md) | Get the fastest speeds on a Mac, and know what fits |
| [03 llama.cpp & GGUF](03-llama-cpp-and-gguf.md) | Master quantization, GPU offload, context, and constrained output |
| [04 Serving at scale (vLLM)](04-serving-at-scale-vllm.md) | Serve many users from a GPU box |
| [05 Integration & operations](05-integration-and-operations.md) | Wire local models into apps (offline RAG, tools), benchmark, and troubleshoot |

> ⚠️ **Dated snapshot — June 2026.** Versions, default ports, and tokens/sec figures move
> fast and are flagged throughout. The *stack model* and the *techniques* are stable.

---

## Next

→ [Ollama & LM Studio](01-ollama-and-lm-studio.md)
