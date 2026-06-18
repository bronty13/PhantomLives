---
title: Ollama & LM Studio (the easy on-ramps)
module: 08 — Local Inference Deep Dive
lesson: 01
est_time: 25 min reading + lab
last_reviewed: 2026-06-18
tags: [ai, local-inference, ollama, lm-studio]
---

# Ollama & LM Studio (the easy on-ramps)

The fastest path from zero to a running local model. Both wrap the same engine
([llama.cpp](03-llama-cpp-and-gguf.md); LM Studio also bundles
[MLX](02-apple-silicon-and-mlx.md)), and both expose an **OpenAI-compatible API** so your
existing code "just works." Pick by taste: **Ollama** is CLI-first and scriptable;
**LM Studio** is a GUI with a model browser.

## Ollama — the `git`-style CLI for models

**Install** (macOS via `brew install --cask ollama`, or `curl -fsSL https://ollama.com/install.sh | sh`).

**Core workflow:**
```bash
ollama run llama3.2          # pull-if-needed, then interactive chat
ollama pull qwen3:8b         # just download
ollama list                  # what's downloaded
ollama ps                    # what's loaded in memory + CPU/GPU split
ollama stop llama3.2         # unload now (frees RAM)
```

`ollama ps` shows the offload split — `100% GPU`, `100% CPU`, or a mix like `48%/52%
CPU/GPU` when a model is too big to fully fit (that split is llama.cpp's `-ngl` offload from
[lesson 03](03-llama-cpp-and-gguf.md), decided automatically).

**Picking a quantization tag** — the colon tag selects the GGUF build
([lesson 03](03-llama-cpp-and-gguf.md) explains the names):
```bash
ollama run qwen3:8b-instruct-q4_K_M   # 4-bit, the sweet spot
ollama run qwen3:8b-instruct-q8_0      # near-lossless, bigger/slower
```

**The OpenAI-compatible server** runs at `http://localhost:11434` (native API at `/api/*`,
OpenAI-compat at `/v1/*`):
```python
from openai import OpenAI
client = OpenAI(base_url="http://localhost:11434/v1", api_key="ollama")  # key ignored
client.chat.completions.create(model="llama3.2",
    messages=[{"role":"user","content":"Say this is a test"}])
```
That `base_url` swap is the whole integration story — see [lesson 05](05-integration-and-operations.md).
(Compat-layer limits: image *URLs* unsupported — base64 only; no `logprobs`/`logit_bias`.)

**Modelfiles** — a Dockerfile for a model (custom system prompt + params):
```dockerfile
FROM llama3.2
SYSTEM "You are a terse senior macOS engineer. Answer in <=3 sentences."
PARAMETER temperature 0.3
PARAMETER num_ctx 8192
```
```bash
ollama create terse-mac -f Modelfile && ollama run terse-mac
```

> ⚠️ **The #1 Ollama surprise: default context is only 4096 tokens.** Long inputs silently
> get truncated ("why did it forget?"). Raise it per model via `PARAMETER num_ctx` in a
> Modelfile, per request, or globally with `OLLAMA_CONTEXT_LENGTH=8192 ollama serve`. Also:
> models unload after **5 minutes** idle by default (`OLLAMA_KEEP_ALIVE` to change).

## LM Studio — the polished GUI (and a real dev server)

For people who want a **chat GUI**, a visual model browser, and a one-toggle server — and,
on a Mac, the **MLX speedup without touching Python**.

- **Discover & download** models in-app (pulls from Hugging Face; shows which quants fit
  your RAM).
- **Two engines, switchable** (manage runtimes with `⌘⇧R`): **GGUF via llama.cpp**
  (cross-platform) and, on Apple Silicon, the faster **MLX** runtime
  ([lesson 02](02-apple-silicon-and-mlx.md)). This dual-engine support is LM Studio's
  standout Mac feature.
- **Local server (OpenAI-compatible) on port `1234`** — flip it on and point any OpenAI SDK
  at `http://localhost:1234/v1`.
- **`lms` CLI** for headless control once you outgrow the GUI.

## Which to use

| | Ollama | LM Studio |
|---|---|---|
| Interface | CLI / background server | GUI (+ optional server & CLI) |
| Best for | Devs, scripting, "just run it" | Discovery, experimentation, non-CLI users |
| Mac MLX speedup | no (llama.cpp/Metal) | **yes** (toggle MLX per model) |
| API port | 11434 | 1234 |

Both are **single-user, laptop-grade** — requests serialize. When you need many concurrent
users, graduate to [vLLM](04-serving-at-scale-vllm.md).

## Lab

1. `ollama run qwen3:8b` and chat.
2. From Python, point the OpenAI SDK at `localhost:11434/v1` and send a message.
3. Make a Modelfile with a custom `SYSTEM` prompt and `num_ctx 8192`; `ollama create` it.
4. (Mac) Install LM Studio, download the same model's **MLX** build, and compare speed.

---

## Next

→ [Apple Silicon & MLX](02-apple-silicon-and-mlx.md)
