---
title: Integration & operations
module: 08 — Local Inference Deep Dive
lesson: 05
est_time: 35 min reading + lab
last_reviewed: 2026-06-18
tags: [ai, local-inference, integration, rag, benchmarking, troubleshooting]
---

# Integration & operations

You can run a model locally — now wire it into real applications, run a whole pipeline
offline, measure it, and fix it when it breaks. This lesson is also the **capstone of the
course**: the payoff is that everything from Modules 2–7 runs unchanged on your own hardware.

## The key unlock: the OpenAI-compatible `base_url`

Ollama, LM Studio, llama.cpp's server, and vLLM **all expose an OpenAI-compatible API.** So
existing OpenAI-SDK code "just works" — you change only the `base_url` (and use a dummy key):

```python
from openai import OpenAI
# Pick ONE backend — only the base_url changes:
client = OpenAI(base_url="http://localhost:11434/v1", api_key="ollama")     # Ollama
# client = OpenAI(base_url="http://localhost:1234/v1",  api_key="lm-studio") # LM Studio
# client = OpenAI(base_url="http://localhost:8080/v1",  api_key="x")         # llama.cpp / mlx_lm
# client = OpenAI(base_url="http://localhost:8000/v1",  api_key="EMPTY")     # vLLM
```

This is the most important integration concept in the module: **the prompting
([Module 2](../part-02-prompt-engineering/00-prompting-fundamentals.md)), RAG
([Module 3](../part-03-rag/00-rag-fundamentals.md)), agent
([Module 4](../part-04-agents-and-tool-use/00-agent-fundamentals.md)), and structured-output
patterns you already learned run against a local model by swapping one URL.** The same trick
works through LangChain / LlamaIndex / LiteLLM.

## Tool calling locally

Local models do OpenAI-style tool calling — send `tools`, get back `tool_calls`, execute,
append a `tool`-role result, call again ([Module 4, lesson 01](../part-04-agents-and-tool-use/01-tool-and-function-calling.md)).
⚠️ **Support varies by model, not just runtime** — it works because models like **Llama 3.1+,
Qwen 2.5+, Mistral-Nemo** were *post-trained* on tool-calling data. A model without that
training tool-calls poorly regardless of the server.

## Structured output locally

- **Ollama:** pass a JSON schema via `format` (the runtime constrains decoding).
- **llama.cpp:** GBNF grammars / `--json-schema` — the most reliable mechanism (sampling only
  accepts tokens the grammar allows). Higher-level libs on the same idea: **Outlines**,
  **Instructor**.
- ⚠️ The schema constrains output but **isn't shown to the model** — also describe the
  structure in the prompt ([lesson 03](03-llama-cpp-and-gguf.md)).

## Offline RAG — the whole pipeline on your machine

Embeddings run locally too, so an entire [RAG pipeline](../part-03-rag/00-rag-fundamentals.md)
can be **fully offline**:

```bash
ollama pull bge-m3                      # or nomic-embed-text, embeddinggemma
curl http://localhost:11434/api/embed -d '{"model":"bge-m3","input":["chunk 1","chunk 2"]}'
```
```python
# or pure-Python, no server:
from sentence_transformers import SentenceTransformer
vecs = SentenceTransformer("BAAI/bge-m3").encode(chunks, normalize_embeddings=True)
```
Pipe vectors into a local vector store (Chroma / Qdrant / FAISS / pgvector) → retrieve → feed
a local chat model. **Nothing leaves the machine** — RAG over private documents with zero
external calls. (Model picks: **BGE-M3** multilingual/hybrid, **Nomic** for long docs,
**MiniLM** fast/light.)

## GUIs (brief)

- **Open WebUI** — the dominant self-hosted, ChatGPT-style UI; runs over Ollama or any
  OpenAI-compatible backend, with built-in RAG. Fastest full front-end.
- **Jan** — native desktop app that bundles its own runtime (no separate Ollama/Docker) —
  best for non-technical users.
- **AnythingLLM** (document/RAG-centric), **text-generation-webui** (developer/research).

## Benchmark your own setup

Measure the two metrics that matter ([Module 7, lesson 04](../part-07-cost-and-latency/04-latency-engineering.md)):
**tokens/sec** and **TTFT**.

- **llama.cpp:** `llama-bench -m model.gguf -p 512 -n 128` (engine-direct, not the HTTP path).
- **Any OpenAI-compatible endpoint:** a tool like `llama-benchy` measures the *HTTP* path —
  what users actually feel. vLLM ships `vllm bench` for load testing.
- **Defensible-benchmark checklist:** record model, quant, context, prompt, temperature, seed,
  runner **version**, hardware, and warm-up state — or the numbers aren't comparable.

## Troubleshooting (the three things that break)

**Out of memory** — in order of speed: (1) reduce context (`num_ctx` / `-c`); (2) offload
fewer layers (`-ngl`) or enable `--flash-attn`; (3) more aggressive quant (Q6/Q8 → Q4_K_M;
vLLM → AWQ/FP8); (4) KV-cache quant; (5) on vLLM, `--gpu-memory-utilization 0.85` /
`--enforce-eager` / lower `--max-model-len`; (6) smaller model.

**Slow generation** — the model spilled to **CPU RAM / swap** (too big to fit → fit it), or
the **wrong backend** (a serial runner under concurrent load → [vLLM](04-serving-at-scale-vllm.md)),
or missing GPU offload.

**Quality problems** — (1) **quant too aggressive** (Q4/INT4 can hurt reasoning/code → step up
to Q5/Q6/FP8 or a bigger model); (2) **wrong chat template** — *the #1 silent quality killer*.
Each model family expects specific role tokens; a mismatched template yields coherent-but-bad
output. Use the runtime's built-in template for that model. (Same chat-template trap as
[Module 6, lesson 02](../part-06-fine-tuning/02-data.md).)

## Privacy & security — the payoff and the caveat

The whole point: **data never leaves the machine** — suitable for regulated or air-gapped
work, and (with offline RAG above) the *entire* pipeline stays local. But the server itself
defaults to **no real auth**: bind it to `127.0.0.1` for local-only use; if you expose it on a
network, put it behind a reverse proxy with auth/TLS — never expose `0.0.0.0` to the internet.
The local "API key" is a dummy unless you add a real gateway.

---

## 🎓 Course capstone — you've completed AI Training

With this module done, you can run the **entire course on your own hardware**:

- **[Choose a model](../part-01-model-landscape/00-how-to-choose-a-model.md)** (M1) — and run
  the open-weight ones here, offline.
- **[Prompt](../part-02-prompt-engineering/00-prompting-fundamentals.md)** it (M2),
  **[ground it with RAG](../part-03-rag/00-rag-fundamentals.md)** (M3) — fully local —
  **[build agents](../part-04-agents-and-tool-use/00-agent-fundamentals.md)** (M4) on it.
- **[Evaluate](../part-05-evaluation/00-the-eval-mindset.md)** it (M5),
  **[fine-tune](../part-06-fine-tuning/00-fundamentals-and-when-to-fine-tune.md)** it (M6),
  and **[engineer its cost and latency](../part-07-cost-and-latency/00-fundamentals-and-the-triangle.md)** (M7).

The throughline of the whole curriculum: **reach for the simplest thing that works, measure
whether it worked, and add complexity only when the eval says you must** — whether that
"thing" is a one-line prompt to a frontier API or a fine-tuned 8B model served from your own
GPU. That judgment — not any single tool — is the skill.

### Where to go from here
Pick a real project and run the loop end to end: choose a model, build the smallest eval that
captures "good," and iterate. Re-verify the dated catalogs against current docs as you go (the
techniques age slowly; the specifics don't). And if you extend this course, see
[HANDOFF.md](../HANDOFF.md).

---

← [Serving at scale (vLLM)](04-serving-at-scale-vllm.md) · ↑ [Module index](../CURRICULUM.md) ·
🏠 [Course home](../README.md)
