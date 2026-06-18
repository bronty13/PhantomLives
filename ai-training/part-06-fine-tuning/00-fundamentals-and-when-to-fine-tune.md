---
title: Fundamentals & when (not) to fine-tune
module: 06 — Fine-tuning & Adaptation
lesson: 00
est_time: 30 min reading
last_reviewed: 2026-06-18
tags: [ai, fine-tuning, adaptation, decision]
---

# Fundamentals & when (not) to fine-tune

**Fine-tuning continues training a model on your own examples so its *weights* shift toward
the behavior you want.** It's the heaviest adaptation lever — and the one most often reached
for too early. This lesson is the durable decision: what fine-tuning is, where it sits among
the alternatives, and when it's the right (and wrong) tool.

The course has been pointing here: [Module 1](../part-01-model-landscape/00-how-to-choose-a-model.md)
and [Module 3](../part-03-rag/00-rag-fundamentals.md) both named fine-tuning as the "teach
behavior, not facts" option. Now we make that precise.

## The adaptation spectrum

Reach for the cheapest, fastest lever that works; escalate only when it provably falls short.

| Technique | Changes | For | Iteration speed |
|---|---|---|---|
| **Prompting / few-shot** | The prompt only | Steer behavior with instructions + examples ([Module 2](../part-02-prompt-engineering/00-prompting-fundamentals.md)) | Instant |
| **RAG** | The context (retrieved docs) | Inject fresh / proprietary **knowledge** ([Module 3](../part-03-rag/00-rag-fundamentals.md)) | Low — update the index, not the model |
| **Fine-tuning** | Model **weights** | Bake in **behavior / style / format / a narrow skill** | High — needs data + a training run |
| **Continued pretraining** | Weights, at scale | Teach a whole new **domain / language** | Highest — large corpora |

## The crucial framing: behavior, not knowledge

This is the single most important — and most durable — idea in the module. OpenAI frames
model optimization as **two axes, not one ladder**:

- **Context optimization** = *what the model needs to **know*** → the **RAG** axis (the
  knowledge is missing, out of date, or proprietary).
- **LLM optimization** = *how the model needs to **act*** → the **fine-tuning** axis (output
  is inconsistent, wrong format, wrong tone, reasoning not followed).

The analogy to remember: **RAG is an open-book exam** (hand the model the textbook at test
time); **fine-tuning is studying** (build the skill into the model itself). They **stack**
when you need fresh knowledge *and* consistent behavior — but they aren't always additive
(once fine-tuning fixes a behavior, adding RAG can even hurt).
[(OpenAI — Optimizing LLM accuracy)](https://developers.openai.com/api/docs/guides/optimizing-llm-accuracy)

> **The cardinal rule:** *don't fine-tune to add knowledge — that's RAG.* Training facts into
> weights causes hallucination and goes stale the moment the facts change.

## When fine-tuning genuinely helps

1. **Consistent output format / structure / tone / style** — the canonical win. If prompting
   gets it right *sometimes*, fine-tuning makes it reliable.
2. **A narrow, specialized task** — classification, extraction, domain-specific generation
   (e.g. text-to-SQL). Reported gains are large (e.g. a fine-tuned small model jumping ~25 F1
   points over its base on a financial-QA task).
3. **Reliability of tool-use / structured output** — turning a flaky behavior dependable.
4. **Latency & cost** — a **small fine-tuned model can beat a large prompted one** *and* run
   cheaper and shorter (it needs fewer in-context examples). This is often the real business
   case.
5. **Distillation** — capture a frontier model's behavior in a small, cheap student
   ([lesson 01](01-methods.md)).

## When NOT to fine-tune

1. **You need fresh / proprietary / changing knowledge** → use **RAG**. (The cardinal rule.)
2. **You haven't exhausted prompting + few-shot + RAG.** Prompt engineering gives
   near-instant results, needs no GPUs, and preserves the base model's general ability.
   Every provider says *prompt-first*.
3. **You have no eval set.** Without one ([Module 5](../part-05-evaluation/00-the-eval-mindset.md))
   you can't tell whether fine-tuning helped — and you can't catch the safety regression it
   may have caused ([lesson 04](04-pitfalls-risks-and-maintenance.md)).
4. **The base model already does the task.** A newer/larger base often erases the need.
5. **Data is scarce or low-quality.** A small *clean* dataset beats a large messy one — but
   garbage data makes fine-tuning actively worse ([lesson 02](02-data.md)).

## The cost you're signing up for

Fine-tuning is not a one-time fix — it's an ongoing liability:

- **Data** must be curated, validated, and decontaminated against your eval set.
- **Training** needs GPUs or a managed service.
- **Maintenance treadmill:** a fine-tune is frozen to a base-model snapshot. It does **not**
  inherit the base's upgrades, and when the base is **deprecated you must re-tune and
  re-validate** ([lesson 04](04-pitfalls-risks-and-maintenance.md)).
- **Safety can degrade** — even on benign data — so you must re-run safety evals every time.

## Provider reality (dated — June 2026)

⚠️ The *availability* of fine-tuning shifts fast; verify before you build:

- **OpenAI's hosted fine-tuning is being wound down** (closed to new users) — don't architect
  new work around it.
- **Claude fine-tuning** is not in the first-party Anthropic API — only via **Amazon
  Bedrock** (region-limited); Anthropic's public stance is prompt/context-first.
- **Gemini fine-tuning** is consolidated onto **Google Vertex AI**.
- **Open-weight DIY** (fine-tune a Llama/Qwen/Mistral yourself with Unsloth/Axolotl/TRL) is
  the most durable route — no vendor can deprecate your model out from under you
  ([lesson 03](03-process-tooling-and-serving.md)).

The *techniques* below are stable; the *who-offers-what* is not.

---

## Next

→ [Methods](01-methods.md)
