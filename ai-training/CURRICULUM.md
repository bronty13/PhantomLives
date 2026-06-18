---
title: AI Training — Curriculum & Build Status
type: curriculum-index
last_reviewed: 2026-06-18
---

# Curriculum & build status

Status legend: ⬜ not started · 🚧 in progress · ✅ done

Update the status column whenever you touch a lesson. This is the authoritative
lesson list — the [README](README.md) module map points here.

## Module 0 — Orientation

| Status | Lesson | File |
|---|---|---|
| ✅ | How to use this course | [part-00-orientation/00-how-to-use-this-course.md](part-00-orientation/00-how-to-use-this-course.md) |
| ⬜ | Vocabulary primer (tokens, context, params, modalities, quantization) | *(planned — currently folded into the Module 1 pages)* |

## Module 1 — Model Landscape *(the first build)*

| Status | Lesson | File |
|---|---|---|
| ✅ | How to choose a model (decision framework) | [part-01-model-landscape/00-how-to-choose-a-model.md](part-01-model-landscape/00-how-to-choose-a-model.md) |
| ✅ | Frontier & proprietary models | [part-01-model-landscape/01-frontier-proprietary-models.md](part-01-model-landscape/01-frontier-proprietary-models.md) |
| ✅ | The open-weight / local ecosystem | [part-01-model-landscape/02-open-weight-local-ecosystem.md](part-01-model-landscape/02-open-weight-local-ecosystem.md) |
| ✅ | Top ~100 local models | [part-01-model-landscape/03-top-100-local-models.md](part-01-model-landscape/03-top-100-local-models.md) |

## Future modules *(not yet built — see [HANDOFF.md](HANDOFF.md))*

| Status | Module | Sketch |
|---|---|---|
| ⬜ | 2 — Prompting & context engineering | Prompt structure, system prompts, caching, structured outputs, when prompting beats fine-tuning. |
| ⬜ | 3 — Retrieval-augmented generation (RAG) | Embeddings, vector stores, chunking, rerankers, grounded citations. |
| ⬜ | 4 — Agents & tool use | Tool/function calling, the agent loop, MCP, multi-agent, when *not* to build an agent. |
| ⬜ | 5 — Evaluation | How to actually measure if a model/prompt is good; eval sets, LLM-as-judge, regression testing. |
| ⬜ | 6 — Fine-tuning & adaptation | LoRA/QLoRA, when fine-tuning helps vs. hurts, data prep, distillation. |
| ⬜ | 7 — Cost & latency engineering | Token economics, batching, caching, model cascades/routing, the build-vs-buy math. |
| ⬜ | 8 — Local inference deep dive | Running models on your own hardware end-to-end (MLX on the Mac, llama.cpp, vLLM serving). |
