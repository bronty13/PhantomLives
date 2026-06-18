---
title: How to use this course (+ vocabulary primer)
module: 00 — Orientation
lesson: 00
est_time: 25 min reading
last_reviewed: 2026-06-18
tags: [ai, orientation, vocabulary]
---

# How to use this course

This is a **practical** AI course. The test of every page is: *does it help you
make a better decision or build a better thing?* If a fact doesn't change what you
do, it's not here.

## The structure, and why it's shaped this way

The AI model world changes weekly. If this course were "here are the best models,"
it would be wrong within a month. So it's built in two layers:

- **Frameworks** (slow-aging): how to *think* about choosing a model, sizing
  hardware, and reasoning about cost. These barely change.
- **Catalogs** (fast-aging): the specific models, prices, and limits as of a dated
  snapshot. These rot fast and carry a `last_reviewed` date + a re-verify note.

**Always read the framework page before the catalog page.** The catalog only makes
sense once you know what questions you're asking of it.

## How to actually use it when you have a real decision

1. Open [Module 1 → How to Choose a Model](../part-01-model-landscape/00-how-to-choose-a-model.md).
2. Identify your **task** (coding? extraction? long-doc analysis?) and your hard
   **constraints** (budget? latency? data can't leave your machine?).
3. The framework narrows you to 2–3 candidate models.
4. Jump to the relevant catalog page for the shortlist.
5. **Re-verify the exact price/limits on the provider's own docs** before you
   commit code or money. The catalog is a starting point, not a contract.

---

# Vocabulary primer

You need these eight concepts before the catalogs are readable. Skim if you know
them.

### Token
The unit models read and bill in — roughly ¾ of a word in English, more for code or
non-English text. **"Tokens," not characters or words, are what you pay for**, and
prices are quoted per **1M tokens**, split into *input* (what you send) and *output*
(what the model generates — usually 3–5× pricier than input).

> Don't estimate token counts with OpenAI's `tiktoken` for non-OpenAI models — every
> family tokenizes differently. Use the provider's own token counter when cost
> matters.

### Context window
The maximum number of tokens a model can "see" at once — your prompt + the
conversation history + its own output all share this budget. In mid-2026, windows
range from ~128K (plenty for most chat) to **1M–10M** (whole codebases, books,
long video). A bigger window costs more to fill and doesn't make the model *smarter*
— it just lets it hold more at once. **Max output** is often a separate, smaller cap
(e.g. 64K–128K) even when the input window is 1M.

### Parameters (the "B" number)
Model size, in billions of weights — `8B`, `70B`, `405B`. More parameters generally
means more capability but more compute/memory to run. For **API** models, you mostly
don't see or care about this. For **local** models it's the single most important
number, because it dictates whether the model fits on your hardware (see
[Module 1 → local ecosystem](../part-01-model-landscape/02-open-weight-local-ecosystem.md)).

### Mixture-of-Experts (MoE) vs. dense
A **dense** model uses all its parameters on every token. An **MoE** model has many
"expert" sub-networks but only activates a few per token — quoted as
**total / active**, e.g. "35B-A3B" = 35B total, 3B active. The payoff: it *runs* at
the speed of its small active set but *thinks* closer to its large total. The catch
(for local use): **all** the experts must still fit in memory. MoE is the defining
architecture of mid-2026 frontier and local models.

### Modalities
What the model can take in / put out beyond text: **vision** (images), **audio**,
**video**, **image generation**. "Multimodal" usually means *text + image input* at
minimum; native **video/audio** understanding is rarer and a real differentiator.

### Reasoning / "thinking" models
Models that spend extra hidden computation working through a problem step-by-step
before answering (you may see this as a "thinking" phase, an `effort` setting, or a
"reasoning" mode). They're markedly better at math, logic, hard coding, and
multi-step planning — but **slower and more expensive**, because you pay for those
hidden reasoning tokens too. Use them when correctness matters more than speed/cost;
don't use them to classify sentiment.

### Quantization
Compressing a model's weights to fewer bits (16-bit → 8/4/2-bit) so it fits in less
memory and runs faster, at a small quality cost. Only relevant for **local** models;
the formats (GGUF, MLX, AWQ, GPTQ, FP8) and which hardware runs them are covered in
the [local ecosystem](../part-01-model-landscape/02-open-weight-local-ecosystem.md)
page. The practical rule: 4-bit (`Q4`) keeps ~95% of quality at ~¼ the size — the
default for running models on your own machine.

### Open-weight vs. proprietary (and the license trap)
- **Proprietary / closed:** you call it via an API, pay per token, can't see or run
  the weights (Claude, GPT, Gemini, Grok flagships).
- **Open-weight:** the weights are downloadable; you can run them yourself, fine-tune
  them, and avoid per-token fees (Llama, Qwen, DeepSeek, Gemma, Mistral, ...).
- **The trap:** "open-weight" ≠ "do anything you want." Licenses vary from truly
  permissive (Apache 2.0 / MIT) to restricted "community" licenses with user caps,
  revenue triggers, or non-commercial clauses. **Read the license before shipping.**

---

## Next

→ [Module 1 — How to Choose a Model](../part-01-model-landscape/00-how-to-choose-a-model.md)
