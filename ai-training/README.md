---
title: AI Training
type: course-home
audience: builder / power-user learning to choose, run, and apply AI models well
scope: practical working knowledge of the AI model landscape and how to use it
status: living document
last_reviewed: 2026-06-18
---

# AI Training — choosing and using AI models like a pro

A self-paced curriculum for getting **genuinely good at the practical side of AI**:
knowing which model to reach for, when to pay for a frontier API vs. run something
locally, how the pieces fit together, and how to apply them without burning money
or shipping the wrong tool.

This is **not** an ML-theory course (no backprop derivations, no "build a
transformer from scratch"). It's a working practitioner's course — the knowledge
you need to make good decisions and build things that work.

It's built the same way as this repo's [`macos-mastery`](../macos-mastery/) course:
plain Markdown, no build step, mirrored into Obsidian by the repo's
`sync-md-to-obsidian.sh` (so **commit new lessons** or they won't appear in
Obsidian).

---

## ⚠️ Read this first: the landscape moves fast

The model world changes **weekly**. Every catalog in this course is a **dated
snapshot** — by the time you read it, prices will have dropped, versions will have
bumped, and a few "flagship" models will have been deprecated. The research behind
the Module 1 catalogs already caught models that were *announced but not shipped*.

So the course is deliberately structured to put the **durable skill first** and the
**perishable facts second**:

- The **decision frameworks** (how to pick a model, how to size hardware, how to
  reason about cost) age slowly — learn these.
- The **model catalogs** (which exact model, what price) age fast — treat them as a
  starting point and **verify against the provider before you commit**.

Every catalog page carries a `last_reviewed` date and a "how to re-verify" note.

---

## How to use this course

1. **Start with [Module 1 → How to Choose a Model](part-01-model-landscape/00-how-to-choose-a-model.md).** It's the spine: a task-and-constraint decision framework that the catalogs hang off of.
2. **Follow the path in [CURRICULUM.md](CURRICULUM.md).** Modules build on each other, but each lesson is self-contained.
3. **Track progress in [PROGRESS.md](PROGRESS.md).**
4. **When you actually need to pick a model**, jump to the catalog page, then re-verify the specific model's price/limits on the provider's own docs (links are in each page).

---

## Module map

| # | Module | What you'll get |
|---|---|---|
| 0 | [Orientation](part-00-orientation/00-how-to-use-this-course.md) | How the course works; the vocabulary you need before the catalogs make sense. |
| 1 | **Model Landscape** | The decision framework + dated catalogs of frontier/proprietary models and open-weight/local models, including a top-~100 local-model list with use cases. |
| 2 | **Prompt Engineering** | The durable principles, the core techniques, how prompting inverted in the reasoning-model era, advanced patterns, and reliability/security/evaluation. |
| 3 | **Retrieval-Augmented Generation (RAG)** | The pipeline and the RAG-vs-long-context-vs-fine-tuning decision; chunking, embeddings & vector stores, retrieval quality, grounded/cited generation, and evaluation/security/production. |
| 4 | **Agents & Tool Use** | When (and when not) to build an agent; tool/function calling, agent architectures & multi-agent, context engineering & memory, MCP, safety/security, and evaluating/operating agents. |
| 5 | **Evaluation** | The eval-driven-development mindset; building golden sets, the grading hierarchy, LLM-as-a-judge, reading benchmarks critically, and rigorous/continuous production eval (stats, A/B, CI, monitoring). |
| 6 | **Fine-tuning & Adaptation** | When (and when not) to fine-tune; methods (LoRA/QLoRA, SFT, DPO, RFT, distillation), the data discipline, process/tooling/serving, and the pitfalls (forgetting, safety degradation, maintenance). |
| 7 | **Cost & Latency Engineering** | The cost/latency/quality triangle; token economics, caching, model right-sizing & routing, latency engineering (TTFT/streaming/throughput), and production economics / build-vs-buy. |
| 8 | **Local Inference Deep Dive** | Running models on your own hardware end-to-end: the local stack, Ollama/LM Studio, Apple Silicon & MLX, llama.cpp/GGUF, vLLM serving, and offline integration/ops. |

> 🎓 **The core curriculum (Modules 0–8) is complete** — the full arc from choosing a model
> to running the whole stack on your own hardware. See [CURRICULUM.md](CURRICULUM.md) for the
> lesson index and [HANDOFF.md](HANDOFF.md) to extend it.

---

## Current contents

**Module 1 — Model Landscape**
- [How to Choose a Model](part-01-model-landscape/00-how-to-choose-a-model.md) — the task × constraint decision framework. **Start here.**
- [Frontier & Proprietary Models](part-01-model-landscape/01-frontier-proprietary-models.md) — Claude, GPT, Gemini, Grok, Llama, Mistral, Nova, Command, DeepSeek, Qwen, and the niche players, with best-use guidance.
- [The Open-Weight / Local Ecosystem](part-01-model-landscape/02-open-weight-local-ecosystem.md) — quantization, hardware sizing, runtimes (Ollama/MLX/llama.cpp/vLLM), licensing traps, how to pick by hardware budget.
- [Top ~100 Local Models](part-01-model-landscape/03-top-100-local-models.md) — a categorized, popularity-anchored catalog with one-line use cases.

**Module 2 — Prompt Engineering**
- [Prompting Fundamentals](part-02-prompt-engineering/00-prompting-fundamentals.md) — what prompting is/isn't, the prerequisites, prompt anatomy, and the durable principles. **Start here.**
- [Core Techniques](part-02-prompt-engineering/01-core-techniques.md) — zero/few-shot, roles, delimiters/XML, structured output, long-context layout, and the prefill caveat.
- [Prompting in the Reasoning Era](part-02-prompt-engineering/02-prompting-reasoning-models.md) — how the playbook inverted: goal-not-steps, effort over prose, be less prescriptive.
- [Advanced Patterns](part-02-prompt-engineering/03-advanced-patterns.md) — CoT variants, self-consistency, chaining, ReAct/tool prompting, meta-prompting, templating + caching.
- [Reliability, Security & Evaluation](part-02-prompt-engineering/04-reliability-security-and-evaluation.md) — hallucination mitigation, prompt injection/jailbreak defense, and how to evaluate/iterate prompts.

**Module 3 — Retrieval-Augmented Generation (RAG)**
- [RAG Fundamentals](part-03-rag/00-rag-fundamentals.md) — the pipeline, why RAG, and the RAG vs. long-context vs. fine-tuning decision. **Start here.**
- [Ingestion & Chunking](part-03-rag/01-ingestion-and-chunking.md) — parsing, chunking strategies, size/overlap, metadata, contextual chunking.
- [Embeddings & Vector Stores](part-03-rag/02-embeddings-and-vector-stores.md) — how embeddings work, current models, vector DBs, ANN indexes.
- [Retrieval Quality](part-03-rag/03-retrieval-quality.md) — hybrid search, reranking, query transformation, contextual retrieval, GraphRAG, agentic RAG.
- [Generation & Prompt Assembly](part-03-rag/04-generation-and-prompt-assembly.md) — grounding, citations, chunk ordering ("lost in the middle"), how many chunks.
- [Evaluation, Security & Production](part-03-rag/05-evaluation-security-and-production.md) — RAG metrics & RAGAS, injection/poisoning/access-control, freshness/latency/cost/caching.

**Module 4 — Agents & Tool Use**
- [Agent Fundamentals](part-04-agents-and-tool-use/00-agent-fundamentals.md) — agent vs. workflow vs. single call, the agent loop, and the "when *not* to build one" gate. **Start here.**
- [Tool & Function Calling](part-04-agents-and-tool-use/01-tool-and-function-calling.md) — the call mechanic, tool_choice/parallel/streaming, and designing tools the model uses well.
- [Agent Architectures & Patterns](part-04-agents-and-tool-use/02-agent-architectures-and-patterns.md) — the workflow taxonomy, autonomous loops (ReAct etc.), and when multi-agent wins or hurts.
- [Context Engineering & Memory](part-04-agents-and-tool-use/03-context-engineering-and-memory.md) — context rot, compaction, context editing, memory tools, and subagent context isolation.
- [MCP & the Tool Ecosystem](part-04-agents-and-tool-use/04-mcp-and-the-tool-ecosystem.md) — what MCP is, its architecture, and its security surface.
- [Safety, Security & Reliability](part-04-agents-and-tool-use/05-safety-security-and-reliability.md) — failure modes, guardrails, human-in-the-loop, least privilege, excessive agency, the lethal trifecta.
- [Evaluating & Operating Agents](part-04-agents-and-tool-use/06-evaluating-and-operating-agents.md) — outcome vs. trajectory eval, pass^k, agent eval sets, and observability.

**Module 5 — Evaluation**
- [The Eval Mindset](part-05-evaluation/00-the-eval-mindset.md) — why eval is the moat, eval-driven development, "look at your data," offline vs. online. **Start here.**
- [Building Eval Sets](part-05-evaluation/01-building-eval-sets.md) — SMART criteria, coverage & negative examples, sourcing, labeling, train/test split, contamination.
- [Grading Methods](part-05-evaluation/02-grading-methods.md) — the reliability hierarchy: code-based, statistical/NLP metrics & their limits, classification metrics, human eval.
- [LLM-as-a-Judge](part-05-evaluation/03-llm-as-judge.md) — the three modes, writing judge prompts, the bias table + mitigations, juries, calibration.
- [Benchmarks & the Landscape](part-05-evaluation/04-benchmarks-and-the-landscape.md) — what benchmarks measure, contamination/saturation/Goodhart, reading leaderboards critically, safety eval.
- [Evaluation in Production](part-05-evaluation/05-evaluation-in-production.md) — statistics (CIs, paired deltas, pass@k vs pass^k), A/B testing, CI gating, online monitoring, tooling.

**Module 6 — Fine-tuning & Adaptation**
- [Fundamentals & When (Not) to Fine-tune](part-06-fine-tuning/00-fundamentals-and-when-to-fine-tune.md) — the adaptation spectrum and the "behavior, not knowledge" decision. **Start here.**
- [Methods](part-06-fine-tuning/01-methods.md) — full vs. PEFT (LoRA/QLoRA), SFT, preference tuning (DPO), RFT/RLVR, distillation, continued pretraining.
- [Data](part-06-fine-tuning/02-data.md) — quality over quantity, the chat-template trap, curation/decontamination, synthetic data, preference pairs.
- [Process, Tooling & Serving](part-06-fine-tuning/03-process-tooling-and-serving.md) — the workflow, hosted vs. DIY, QLoRA hardware, hyperparameters, and multi-LoRA serving.
- [Pitfalls, Risks & Maintenance](part-06-fine-tuning/04-pitfalls-risks-and-maintenance.md) — catastrophic forgetting, overfitting, safety degradation, privacy, and the re-tuning treadmill.

**Module 7 — Cost & Latency Engineering**
- [Fundamentals & the Triangle](part-07-cost-and-latency/00-fundamentals-and-the-triangle.md) — LLM economics, the cost/latency/quality triangle, the levers, and measuring. **Start here.**
- [Token Economics](part-07-cost-and-latency/01-token-economics.md) — input/output asymmetry, context as the master knob, hidden reasoning tokens, batch APIs.
- [Caching](part-07-cost-and-latency/02-caching.md) — prompt/prefix caching (the biggest lever), semantic & embedding caching, KV/CAG, the savings-vs-risk hierarchy.
- [Model Selection & Routing](part-07-cost-and-latency/03-model-selection-and-routing.md) — right-sizing, cascades (FrugalGPT), routers (RouteLLM), distillation, speculative decoding.
- [Latency Engineering](part-07-cost-and-latency/04-latency-engineering.md) — TTFT/TPOT & prefill-vs-decode, streaming, output reduction, prefix cache, and the throughput↔latency tension.
- [Production Economics & Build-vs-Buy](part-07-cost-and-latency/05-production-economics-and-build-vs-buy.md) — cost attribution, budgets/guardrails, the API-vs-self-host math, batch, and FinOps for AI.

**Module 8 — Local Inference Deep Dive**
- [Why Local, and the Local Stack](part-08-local-inference/00-why-and-the-local-stack.md) — the engine/front-end/server mental model and hardware reality. **Start here.**
- [Ollama & LM Studio](part-08-local-inference/01-ollama-and-lm-studio.md) — the easy on-ramps: pull/run, the OpenAI-compatible server, Modelfiles, the context gotcha.
- [Apple Silicon & MLX](part-08-local-inference/02-apple-silicon-and-mlx.md) — unified memory, the fit table, mlx-lm, and why MLX is fastest on a Mac.
- [llama.cpp & GGUF](part-08-local-inference/03-llama-cpp-and-gguf.md) — the engine: quantization in depth, GPU offload, context/KV cache, GBNF grammars.
- [Serving at Scale (vLLM)](part-08-local-inference/04-serving-at-scale-vllm.md) — when to graduate, PagedAttention/continuous batching, multi-GPU, multi-LoRA serving.
- [Integration & Operations](part-08-local-inference/05-integration-and-operations.md) — the OpenAI-compatible base_url unlock, offline RAG, benchmarking, troubleshooting (+ the course capstone).

---

*Built and maintained inside `~/dev/PhantomLives/ai-training/`. To extend it, read [HANDOFF.md](HANDOFF.md).*
