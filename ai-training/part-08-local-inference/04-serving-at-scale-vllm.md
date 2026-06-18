---
title: Serving at scale (vLLM)
module: 08 — Local Inference Deep Dive
lesson: 04
est_time: 30 min reading + lab
last_reviewed: 2026-06-18
tags: [ai, local-inference, vllm, serving, multi-lora]
---

# Serving at scale (vLLM)

Ollama and LM Studio are single-user runners — requests **serialize** (a second request
queues behind the first). When you need to serve *many concurrent users* from a GPU box, you
graduate to a real inference server. The default choice is **vLLM**. This is the hands-on
side of [Module 7's throughput↔latency](../part-07-cost-and-latency/04-latency-engineering.md)
and [build-vs-buy](../part-07-cost-and-latency/05-production-economics-and-build-vs-buy.md)
lessons.

> ⚠️ **vLLM is Linux + GPU first.** On a Mac, stay on Ollama / LM Studio / llama.cpp; the
> vLLM examples here assume a Linux NVIDIA/AMD box.

## When to graduate

| Stay on Ollama / LM Studio | Move to vLLM |
|---|---|
| One developer, a desktop chat, a script | 5+ concurrent users, or growth past 2–3 simultaneous requests |
| Prototyping / local dev | Latency SLAs, production traffic |

The reason: Ollama/llama.cpp lack mature **continuous batching**, so concurrent requests
largely serialize; vLLM keeps the GPU busy across many requests at once. Reported gaps are
large (multiples of throughput at 8+ concurrent users) — *vendor benchmarks, directional
only; measure your own ([lesson 05](05-integration-and-operations.md))*.

## Install & serve

```bash
uv venv --python 3.12 --seed && source .venv/bin/activate
uv pip install vllm --torch-backend=auto      # NVIDIA CUDA

vllm serve Qwen/Qwen2.5-7B-Instruct           # OpenAI-compatible server on :8000
```
```python
from openai import OpenAI
client = OpenAI(api_key="EMPTY", base_url="http://localhost:8000/v1")
client.chat.completions.create(model="Qwen/Qwen2.5-7B-Instruct",
    messages=[{"role":"user","content":"Hi"}])
```
Exposes `/v1/chat/completions`, `/v1/completions`, and `/v1/embeddings`.

## Why throughput beats llama.cpp under load

Two mechanisms (the same ones from [Module 7](../part-07-cost-and-latency/04-latency-engineering.md),
here as *why you'd run vLLM*):

- **PagedAttention** — manages the KV cache in fixed-size pages like OS virtual memory, with
  near-zero fragmentation → packs **2–4× more concurrent users into the same VRAM.**
- **Continuous (in-flight) batching** — new requests join the running GPU batch as they
  arrive and finished ones free their slot immediately, instead of waiting for a whole static
  batch.

## Multi-GPU

```bash
vllm serve <model> --tensor-parallel-size 4                      # split each layer across 4 GPUs (1 node)
vllm serve <model> --tensor-parallel-size 8 --pipeline-parallel-size 2   # 2 nodes × 8 GPUs
```
Rule of thumb: **tensor-parallel-size = GPUs per node**, **pipeline-parallel-size = number of
nodes** (Ray for multi-node).

## Quantization for serving

| Method | Bits | Best on |
|---|---|---|
| **FP8** | 8 | Hopper/Blackwell — best quality+speed |
| **AWQ** | INT4 | Turing+ — fit bigger models on smaller/older cards |
| **GPTQ** | INT4/8 | Volta→Hopper (Marlin kernels) |

```bash
vllm serve <awq-model> --quantization awq
```

## Multi-LoRA — one base, many adapters

The big efficiency unlock (and the serving side of [Module 6](../part-06-fine-tuning/03-process-tooling-and-serving.md)):
keep **one base model in VRAM** plus many lightweight LoRA adapters, each addressable by name
via the `model` field.
```bash
vllm serve meta-llama/Llama-3.2-3B-Instruct --enable-lora \
  --lora-modules sql-lora=<hf-adapter-repo>
# client requests model="sql-lora" → the adapter; model=<base> → the base
```
Runtime load/unload is supported too (`/v1/load_lora_adapter`).

## VRAM rules of thumb (weights only; KV cache adds on top)

- FP16 ≈ **2 GB / 1B params** · FP8 ≈ **1 GB / 1B** · INT4 (AWQ/GPTQ) ≈ **0.5 GB / 1B**.
- A 70B at FP8 ≈ **70 GB** → barely fits one 80 GB GPU before KV cache.
- An 8B serves comfortably on a 24 GB card; multi-GPU TP is for models that don't fit one.

## The other engines (brief)

| Engine | Best at |
|---|---|
| **vLLM** | The default general-purpose server — throughput + flexibility + low ops |
| **SGLang** | Prefix-heavy workloads (agents, RAG, function-calling) via RadixAttention prefix reuse |
| **TensorRT-LLM** | Max raw throughput via compiled engines — if you can absorb per-model compile time + NVIDIA lock-in |
| **TGI** | ⚠️ **In maintenance mode (since early 2026)** — older tutorials recommending it first are stale; pick one of the above |

## Lab (needs a Linux GPU box)

1. `vllm serve` a 7–8B model; hit it from the OpenAI SDK.
2. Load-test with concurrent requests (e.g. `vllm bench`) and compare tokens/sec to Ollama on
   the same hardware.
3. Serve a base model `--enable-lora` with one adapter; switch between base and adapter via
   the `model` field.

---

## Next

→ [Integration & operations](05-integration-and-operations.md)
