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
| 1 | **Model Landscape** (the first build) | The decision framework + dated catalogs of frontier/proprietary models and open-weight/local models, including a top-~100 local-model list with use cases. |
| 2+ | *(future)* | Prompting, RAG, agents & tool use, evals, fine-tuning, cost engineering, local-inference deep dive — see [HANDOFF.md](HANDOFF.md). |

---

## Current contents (Module 1 — Model Landscape)

- [How to Choose a Model](part-01-model-landscape/00-how-to-choose-a-model.md) — the task × constraint decision framework. **Start here.**
- [Frontier & Proprietary Models](part-01-model-landscape/01-frontier-proprietary-models.md) — Claude, GPT, Gemini, Grok, Llama, Mistral, Nova, Command, DeepSeek, Qwen, and the niche players, with best-use guidance.
- [The Open-Weight / Local Ecosystem](part-01-model-landscape/02-open-weight-local-ecosystem.md) — quantization, hardware sizing, runtimes (Ollama/MLX/llama.cpp/vLLM), licensing traps, how to pick by hardware budget.
- [Top ~100 Local Models](part-01-model-landscape/03-top-100-local-models.md) — a categorized, popularity-anchored catalog with one-line use cases.

---

*Built and maintained inside `~/dev/PhantomLives/ai-training/`. To extend it, read [HANDOFF.md](HANDOFF.md).*
