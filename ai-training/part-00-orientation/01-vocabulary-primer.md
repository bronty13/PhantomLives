---
title: Vocabulary primer
module: 00 — Orientation
lesson: 01
est_time: 25 min reading
last_reviewed: 2026-06-26
tags: [ai, orientation, vocabulary, glossary]
---

# Vocabulary primer

Before the rest of the course is readable, you need a working grasp of the
vocabulary it's built on. This is a **practical glossary** — each term gets a
one- or two-line definition and a pointer to the module that teaches it in depth.
You don't need to memorize it; skim it now, and come back when a term shows up.

Terms are grouped: the **essential handful** you need before anything else, then
**model anatomy**, **capabilities & behavior**, **access & licensing**, the
**application patterns** that name whole modules, and a few **operational** terms.

---

## The essential handful

These five make the model catalogs and the rest of the course legible.

### Token
The unit models read and bill in — roughly ¾ of a word in English, more for code
or non-English text. **"Tokens," not characters or words, are what you pay for**,
and prices are quoted per **1M tokens**, split into *input* (what you send) and
*output* (what the model generates — usually 3–5× pricier than input). The deep
dive is [Module 7 → Token economics](../part-07-cost-and-latency/01-token-economics.md).

> Don't estimate token counts with one model family's tokenizer for another —
> every family tokenizes differently. Use the provider's own counter when cost
> matters.

### Context window
The maximum number of tokens a model can "see" at once — your prompt + the
conversation history + its own output all share this budget. In mid-2026, windows
range from ~128K (plenty for most chat) to **1M–10M** (whole codebases, books,
long video). A bigger window costs more to fill and doesn't make the model
*smarter* — it just lets it hold more at once. **Max output** is often a separate,
smaller cap (e.g. 64K–128K) even when the input window is 1M.

### Prompt and completion
The **prompt** is everything you send the model (instructions + context +
question); the **completion** (or *response*) is what it generates back. Most of
this course — especially [Module 2](../part-02-prompt-engineering/00-prompting-fundamentals.md)
— is about shaping the prompt to get a better completion.

### Inference vs. training
**Training** is the (enormous, one-time) process of creating a model's weights
from data. **Inference** is *running* a finished model to get an answer — what
happens every time you call it. As a practitioner you almost always do inference;
training (or its lighter cousin, fine-tuning) is [Module 6](../part-06-fine-tuning/00-fundamentals-and-when-to-fine-tune.md).
The cost distinction matters: for most LLM apps the bill is **inference, forever**
([Module 13](../part-13-llmops/00-what-is-llmops.md)).

### Temperature (and sampling)
A knob (0–~2) controlling randomness: **low temperature** = more focused,
deterministic output; **high** = more varied, creative. Even at temperature 0 the
output isn't perfectly repeatable — LLMs are *non-deterministic* by nature, a fact
that shapes evaluation ([Module 5](../part-05-evaluation/00-the-eval-mindset.md))
and reliability ([Module 13](../part-13-llmops/03-reliability-engineering.md)).
*(Note: the newest reasoning models often remove this knob in favor of an `effort`
setting — see below.)*

---

## Model anatomy

### Parameters (the "B" number)
Model size, in billions of weights — `8B`, `70B`, `405B`. More parameters generally
means more capability but more compute/memory to run. For **API** models you mostly
don't see or care about this; for **local** models it's the single most important
number, because it dictates whether the model fits on your hardware
([Module 1 → local ecosystem](../part-01-model-landscape/02-open-weight-local-ecosystem.md),
[Module 8](../part-08-local-inference/00-why-and-the-local-stack.md)).

### Mixture-of-Experts (MoE) vs. dense
A **dense** model uses all its parameters on every token. An **MoE** model has many
"expert" sub-networks but activates only a few per token — quoted as
**total / active**, e.g. "35B-A3B" = 35B total, 3B active. It *runs* at the speed
of its small active set but *thinks* closer to its large total. The catch for local
use: **all** the experts must still fit in memory. MoE is the defining architecture
of mid-2026 frontier and local models.

### Weights
The learned numbers that *are* the model. "Open-weight" means these are
downloadable (see below); "the weights" and "the model" are used interchangeably.

### Quantization
Compressing a model's weights to fewer bits (16-bit → 8/4/2-bit) so it fits in less
memory and runs faster, at a small quality cost. Only relevant for **local** models;
the formats (GGUF, MLX, AWQ, GPTQ, FP8) and which hardware runs them are
[Module 8 → llama.cpp & GGUF](../part-08-local-inference/03-llama-cpp-and-gguf.md).
Practical rule: 4-bit (`Q4`) keeps ~95% of quality at ~¼ the size — the default for
running models on your own machine.

---

## Capabilities & behavior

### Modalities
What the model can take in / put out beyond text: **vision** (images), **audio**,
**video**, **image generation**. "Multimodal" usually means *text + image input* at
minimum; native **video/audio** understanding is rarer and a real differentiator.
The whole of [Module 9](../part-09-multimodal/00-multimodal-fundamentals.md) is the
modality grid.

### Reasoning / "thinking" models (and effort)
Models that spend extra hidden computation working through a problem step-by-step
before answering (you may see this as a "thinking" phase, an **`effort`** setting,
or a "reasoning" mode). They're markedly better at math, logic, hard coding, and
multi-step planning — but **slower and more expensive**, because you pay for those
hidden reasoning tokens too. Use them when correctness matters more than speed/cost;
don't use them to classify sentiment. Prompting them is *different* — see
[Module 2 → the reasoning era](../part-02-prompt-engineering/02-prompting-reasoning-models.md).

### Hallucination
When a model generates confident, plausible-sounding content that is **wrong or
fabricated** (a made-up citation, a non-existent API, a false fact). It's intrinsic
to how LLMs work, not a fixable bug — so much of the course is about *mitigating* it:
grounding ([Module 3 RAG](../part-03-rag/00-rag-fundamentals.md)), evaluation
([Module 5](../part-05-evaluation/00-the-eval-mindset.md)), and designing the UI to
make being wrong cheap ([Module 11](../part-11-product-ux/04-designing-for-failure.md)).

---

## Access & licensing

### Open-weight vs. proprietary (and the license trap)
- **Proprietary / closed:** you call it via an API, pay per token, can't see or run
  the weights (Claude, GPT, Gemini, Grok flagships).
- **Open-weight:** the weights are downloadable; you can run them yourself, fine-tune
  them, and avoid per-token fees (Llama, Qwen, DeepSeek, Gemma, Mistral, …).
- **The trap:** "open-weight" ≠ "do anything you want." Licenses vary from truly
  permissive (Apache 2.0 / MIT) to restricted "community" licenses with user caps,
  revenue triggers, or non-commercial clauses. **Read the license before shipping**
  ([Module 1 → local ecosystem](../part-01-model-landscape/02-open-weight-local-ecosystem.md)).

### API vs. local (vs. self-host)
**API** = call someone else's hosted model (simplest, per-token cost, your data
leaves your machine). **Local** = run a model on your own device
([Module 8](../part-08-local-inference/00-why-and-the-local-stack.md)). **Self-host**
= run an open model on your own server infrastructure at scale. The choice is a
[Module 7 build-vs-buy](../part-07-cost-and-latency/05-production-economics-and-build-vs-buy.md)
decision.

---

## Application patterns (these name whole modules)

### Embedding
A model that turns text (or an image) into a **vector** — a list of numbers
capturing its meaning — so that similar things sit close together in vector space.
The foundation of semantic search and RAG. Deep dive:
[Module 3 → embeddings & vector stores](../part-03-rag/02-embeddings-and-vector-stores.md).

### Vector database
A store optimized for finding the **nearest** vectors to a query vector (semantic
search). The retrieval engine under RAG ([Module 3](../part-03-rag/02-embeddings-and-vector-stores.md)).

### RAG (Retrieval-Augmented Generation)
Retrieving relevant documents and putting them *in the prompt* so the model answers
from *your* data instead of (only) its training. The standard way to ground a model
in current, private, or domain-specific knowledge — all of
[Module 3](../part-03-rag/00-rag-fundamentals.md).

### Fine-tuning (and LoRA)
Continuing a model's training on your own examples to change its **behavior** (tone,
format, a narrow skill) — *not* to teach it new facts (that's RAG's job). **LoRA /
QLoRA** are the cheap, popular techniques that adapt a model without retraining all
its weights. Decision framework and methods:
[Module 6](../part-06-fine-tuning/00-fundamentals-and-when-to-fine-tune.md).

### Agent (and tool / function calling)
An **agent** is an LLM that runs in a loop, deciding which **tools** to call to
accomplish a goal — where a *tool* (a.k.a. *function call*) is a capability you give
the model (search, run code, query a DB). Agents are
[Module 4](../part-04-agents-and-tool-use/00-agent-fundamentals.md); applied to code,
[Module 10](../part-10-coding-agents/00-the-coding-agent-landscape.md).

### MCP (Model Context Protocol)
An open standard for connecting an agent to external tools and data — "USB-C for AI
tools." Its agent-to-agent sibling is **A2A**. Both in
[Module 4 → MCP & the tool ecosystem](../part-04-agents-and-tool-use/04-mcp-and-the-tool-ecosystem.md)
and [Module 4 → interoperability](../part-04-agents-and-tool-use/07-agent-interoperability-and-a2a.md).

### Eval (evaluation)
A systematic test of an AI system's quality — the AI equivalent of a test suite, and
arguably the most important discipline in the course because LLM failures are
*silent*. The whole of [Module 5](../part-05-evaluation/00-the-eval-mindset.md).

---

## A couple of operational terms

### Latency & TTFT
**Latency** is how long a response takes; **time-to-first-token (TTFT)** is how long
until the *first* token arrives — and TTFT, not total time, is what makes a streaming
product *feel* fast ([Module 7](../part-07-cost-and-latency/04-latency-engineering.md),
[Module 11](../part-11-product-ux/01-latency-and-perceived-performance.md)).

### Prompt caching
Reusing the model's processing of a repeated prompt prefix to cut cost and latency —
one of the biggest practical levers in production
([Module 7 → caching](../part-07-cost-and-latency/02-caching.md)).

`★ Insight ─────────────────────────────────────`
- **The vocabulary sorts into a few buckets:** what you pay for (tokens, context),
  what the model *is* (parameters, MoE, quantization), what it can *do* (modalities,
  reasoning), how you *reach* it (API/local, open/proprietary), and the *patterns*
  you build with it (embeddings, RAG, agents, eval). Each pattern names a module.
- **You don't need to memorize this** — you need to recognize a term when it
  appears and know which module owns it. Come back here whenever a word doesn't land.
`─────────────────────────────────────────────────`

## Next

→ [Module 1 — How to Choose a Model](../part-01-model-landscape/00-how-to-choose-a-model.md)
— the decision framework the whole course hangs off.
