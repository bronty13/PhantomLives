---
title: Apple Silicon & MLX
module: 08 — Local Inference Deep Dive
lesson: 02
est_time: 30 min reading + lab
last_reviewed: 2026-06-18
tags: [ai, local-inference, apple-silicon, mlx, unified-memory]
---

# Apple Silicon & MLX

This repo's primary platform is Apple Silicon, and Macs are genuinely excellent for local
LLMs — so this lesson gets real weight. The two things that make a Mac good here: **unified
memory** and **MLX**, Apple's native inference engine.

## Why Apple Silicon punches above its weight

**Unified memory** is the headline. CPU, GPU, and Neural Engine share **one** RAM pool with
no copying — so your usable "VRAM" is *most of system RAM*, not a small separate buffer. A
64 GB MacBook can load a 70B model at 4-bit and start generating; a 24 GB discrete GPU
(higher bandwidth, but capped) simply can't fit it. **Memory bandwidth** is the real
token-generation limiter, and it climbs by tier (Pro < Max < the newest M-series).

### "How big a model fits?" (4-bit, rule of thumb)

| RAM | Comfortable class | Example |
|---|---|---|
| 8 GB | 3–4B | Llama 3.2 3B |
| 16 GB | 7–8B | Llama 3.1 8B |
| 24 GB | 13–14B | Qwen 14B |
| 32 GB | 30B MoE (2026 sweet spot) | Qwen3-Coder-30B-A3B |
| 64 GB | 70B dense | Llama 3.1 70B |
| 96–128 GB | 70B higher-precision / large MoE | Mixtral 8x22B |

Context/KV cache eats extra on top ([lesson 03](03-llama-cpp-and-gguf.md)). Ballpark speeds
on a high-end M-series at 4-bit: 7B ≈ 50–70 tok/s, 30B MoE ≈ ~100+ tok/s, 70B ≈ ~12–15
tok/s. *(Vendor/blog numbers — treat as ballpark; they move with chip, quant, context.)*

> ⚠️ **The GPU wired-memory limit.** macOS reserves RAM for the system and won't hand it all
> to the GPU. You *can* raise the ceiling — `sudo sysctl iogpu.wired_limit_mb=<MB>` (macOS
> 14+) — but it's **non-persistent** (resets on reboot) and **dangerous near 100%**: leave
> ~8–16 GB for the system or you'll get beachballs and lockups.

## MLX — Apple's native engine

MLX is Apple's array framework (`ml-explore`); **`mlx-lm`** is the LLM package on top.

```bash
pip install mlx-lm

# one-shot generate (downloads from HF on first run)
mlx_lm.generate --model mlx-community/Mistral-7B-Instruct-v0.3-4bit --prompt "hello"

# interactive chat (keeps context)
mlx_lm.chat --model mlx-community/Qwen3-8B-4bit
```

- **Models live in the `mlx-community` HF org** (`huggingface.co/mlx-community`) — thousands
  pre-converted; the convention is to append `-4bit` / `-8bit` to a model name.
- **Convert/quantize your own** in seconds: `mlx_lm.convert --model <hf-repo> -q` (4-bit
  default; `--upload-repo` to share).
- **OpenAI-compatible server** (defaults to port **8080**):
  ```bash
  mlx_lm.server --model mlx-community/Qwen3-8B-4bit
  # POST localhost:8080/v1/chat/completions   (dev-only; minimal security)
  ```
- **Python API:**
  ```python
  from mlx_lm import load, generate
  model, tok = load("mlx-community/Qwen3-8B-4bit")
  prompt = tok.apply_chat_template([{"role":"user","content":"Hi"}], add_generation_prompt=True)
  print(generate(model, tok, prompt=prompt, verbose=True))
  ```

> ⚠️ **Port collision:** `mlx_lm.server` *and* llama.cpp's `llama-server` both default to
> **8080**. Give one a different `--port` if running both.

## Why MLX beats llama.cpp on M-series

MLX is written for Apple's GPU and (on the newest M-series) the per-core neural accelerators
that llama.cpp's Metal backend can't reach. Reported: **~30–60% faster generation and several×
faster prompt processing** on recent chips (the gap is smaller on M1/M2). For most Mac users
the trade-off is: **MLX for speed, GGUF/llama.cpp for the widest model/tool compatibility.**

**The easiest way to get the MLX speedup without Python:** LM Studio
([lesson 01](01-ollama-and-lm-studio.md)) ships the MLX engine and lets you pick it per model
on Apple Silicon — same GUI, faster backend.

> **This repo already does this.** The `transcribe/` subproject runs the **MLX port of
> Whisper** on Apple Silicon — same MLX family of tooling, applied to speech-to-text. Local
> inference on the Mac isn't theoretical here; it's already in production in the monorepo.

## Lab

1. `pip install mlx-lm`, then `mlx_lm.generate` a 4-bit model from `mlx-community`.
2. Start `mlx_lm.server` and hit `localhost:8080/v1/chat/completions` from the OpenAI SDK.
3. (If you have LM Studio) load the same model as **GGUF** and as **MLX** and compare tok/s.
4. `mlx_lm.convert` an HF model to 4-bit and run your own conversion.

---

## Next

→ [llama.cpp & GGUF](03-llama-cpp-and-gguf.md)
