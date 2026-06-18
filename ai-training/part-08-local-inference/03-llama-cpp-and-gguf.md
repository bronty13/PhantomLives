---
title: llama.cpp & GGUF
module: 08 — Local Inference Deep Dive
lesson: 03
est_time: 35 min reading + lab
last_reviewed: 2026-06-18
tags: [ai, local-inference, llama-cpp, gguf, quantization]
---

# llama.cpp & GGUF

llama.cpp is the **engine under Ollama and LM Studio** — learning it directly gives you the
most control over quantization, memory, and output. (Repo lives at `ggml-org/llama.cpp`.)
This deepens the quantization overview from [Module 1, lesson 02](../part-01-model-landscape/02-open-weight-local-ecosystem.md).

```bash
brew install llama.cpp        # or grab prebuilt binaries from the releases page
```

## GGUF — the format

A single file holding quantized weights **plus metadata** (tokenizer, chat template,
config). It's what Ollama/LM Studio download and what most Hugging Face quant repos ship.

## Quantization, in depth

Naming is `Q<bits>_<variant>`. Modern **K-quants** use super-blocks with per-block scales;
the trailing letter is a size/quality tier *within* the bit width — **S/M/L** = Small/Medium/
Large (M and L spend extra bits on the most sensitive tensors → better, bigger).

The real tradeoff (Llama-3.1-8B, from llama.cpp's quantize README):

| Method | Bits/wt | Size | Note |
|---|---|---|---|
| Q2_K | 3.2 | 2.95 GiB | small, noticeable loss |
| Q3_K_M | 4.0 | 3.74 GiB | |
| **Q4_K_M** | **4.9** | **4.58 GiB** | **the community sweet spot** |
| Q5_K_M | 5.7 | 5.33 GiB | a touch better, ~16% bigger |
| Q6_K | 6.6 | 6.14 GiB | near-lossless |
| Q8_0 | 8.5 | 7.95 GiB | effectively lossless, large |
| F16 | 16 | 14.96 GiB | unquantized baseline |

Teaching points beyond "Q4 is the sweet spot":

- **Bigger quants generate *slower*, not faster.** Token generation is memory-bandwidth-
  bound, so a larger file moves more bytes per token — Q8_0 is half F16's size but *slower*
  than Q4. (Counter-intuitive, and worth internalizing.)
- **Q6_K/Q8_0** are "I have RAM to spare, want max fidelity"; the Q4→Q6 quality gain is small
  for most tasks.
- **Below Q4, prefer I-quants.** **I-quants (IQ*)** use codebooks for better quality-per-bit
  and shine at low bit-widths — **IQ4_XS can match Q4_K_M at a smaller size**, letting a 70B
  fit in less RAM. They're meant to be built with an **importance matrix (imatrix)** — a
  calibration pass recording which weights matter, so bits go where they count (cuts
  perplexity ~10–30% vs naïve quantization). **Use imatrix for anything below Q5_K_M.**

## Running it

```bash
llama-cli -m model.gguf -cnv                 # interactive chat (auto-detects template)
llama-server -m model.gguf --port 8080       # OpenAI-compatible server + built-in web UI
# → POST http://localhost:8080/v1/chat/completions
```

## The fit knobs

### GPU offload (`-ngl`) — fitting a model that doesn't fully fit
`-ngl N` / `--n-gpu-layers N` puts N transformer layers on the GPU, the rest on CPU:
```bash
llama-server -m model.gguf -ngl 99    # offload everything (big number = "all")
llama-server -m model.gguf -ngl 20    # partial offload when VRAM is tight
```
On Apple Silicon (unified memory) you usually offload everything; on a discrete GPU you tune
N down until it fits. (Ollama's `48%/52% CPU/GPU` line is exactly this, automated.)

### Context & KV cache — the hidden memory hog
```bash
llama-server -m model.gguf -c 8192                 # 8K context
llama-server -m model.gguf -c 32768 --flash-attn   # bigger context; flash-attn cuts KV memory
```
The **KV cache grows linearly with context**, so a model that "fits" at 4K can OOM at 32K.
Levers: smaller `-c`, `--flash-attn`, and KV-cache quantization (`--cache-type-k q8_0`).

## Constrained output: GBNF grammars
llama.cpp can *force* output to match a grammar — the most reliable way to get valid JSON
locally:
```bash
llama-cli -m model.gguf --grammar-file grammars/json.gbnf -p "List 3 fruits as JSON"
# or pass a JSON schema; llama.cpp compiles it to a grammar:
llama-server -m model.gguf --json-schema '{"type":"object","properties":{"name":{"type":"string"}}}'
```
> ⚠️ **Gotcha:** the grammar constrains the *output* but is **not shown to the model** — it
> can't "see" the schema. Also describe the structure in the prompt, or you get
> valid-but-wrong JSON. (More structured-output options in [lesson 05](05-integration-and-operations.md).)

## Backends
First-class **Metal** (Apple Silicon), **CUDA** (NVIDIA), **HIP/ROCm** (AMD), **Vulkan**
(cross-vendor), and **CPU**. A `brew` install or prebuilt binary picks the right one
automatically.

## Lab

1. Download a Q4_K_M GGUF and run `llama-cli -cnv`.
2. Start `llama-server`, hit `/v1/chat/completions`, and open its web UI in a browser.
3. On a discrete GPU, lower `-ngl` until it fits; watch tok/s change. On a Mac, bump `-c` to
   32768 and watch memory climb.
4. Constrain output to a JSON schema with `--json-schema` and confirm every response parses.

---

## Next

→ [Serving at scale (vLLM)](04-serving-at-scale-vllm.md)
