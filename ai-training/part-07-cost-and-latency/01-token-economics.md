---
title: Token economics
module: 07 — Cost & Latency Engineering
lesson: 01
est_time: 30 min reading
last_reviewed: 2026-06-18
tags: [ai, cost, tokens, batch-api]
---

# Token economics

The bill is `(input_tokens × input_rate) + (output_tokens × output_rate)`, summed over
every call. This lesson is how to make each term smaller.

> ⚠️ **Dated snapshot — June 2026.** Exact prices and discount percentages change monthly.
> Learn the *ratios and shapes* (output ≫ input, ~50% batch discount); re-check the numbers
> on the provider's live pricing page before they go in a cost model.

## The four facts that drive cost

### 1. Output costs ~3–8× input
Output tokens are generated one at a time and priced several times higher than input (which
is processed in parallel during prefill). Across providers the multiple runs ~5× (Claude) to
~8× (some others). **Consequence:** the single cheapest optimization is usually **shorter
output** — a verbose model that "thinks out loud" in its final answer is far more expensive
than its input count suggests.

### 2. Context is billed on *every* call — the master knob
The API is **stateless**: the model remembers nothing, so you re-send the system prompt,
full conversation history, RAG chunks, and tool definitions on **every request**. They're
all re-billed as input each time, so in a long chat or agent loop input cost grows roughly
**quadratically** with length (turn N pays for turns 1…N−1). This is why **caching**
([lesson 02](02-caching.md)) and **context trimming** are the highest-leverage cost levers.

### 3. Hidden reasoning tokens
Reasoning/"thinking" models generate an internal chain of thought **before** the visible
answer, and **those tokens are billed as output** — at the expensive rate — even when the
raw reasoning is never returned to you. So measure **`usage.output_tokens`**, not the length
of the rendered answer, and **tune reasoning effort down** for routine work (lower effort
often matches higher-effort quality at a fraction of the tokens —
[Module 1](../part-01-model-landscape/01-frontier-proprietary-models.md) on effort).

### 4. Long-context premiums
A big context window isn't free even before you fill it: some models **double their rate
above a threshold** (e.g. >200K tokens), and you pay for the whole window on every call.
"Just stuff everything into the 1M window" can quietly cross you into a 2× tier — trim before
the boundary.

## Levers to cut tokens

- **Trim / compress context** — the biggest lever, because context is re-billed every call.
  Remove dead history, summarize old turns, retrieve fewer/smaller chunks. For long agents,
  **context editing** (prune stale tool results) and **compaction** (summarize near the
  limit) automate this ([Module 4, lesson 03](../part-04-agents-and-tool-use/03-context-engineering-and-memory.md)).
- **Control output length** — set a sensible `max_tokens` (a hard cap), prompt for
  conciseness, use stop sequences, and lower reasoning effort. Disproportionately effective
  because output is 3–8× input.
- **Structured / concise outputs** — a schema-constrained response
  ([Module 2, lesson 01](../part-02-prompt-engineering/01-core-techniques.md)) eliminates
  filler tokens and is parseable.
- **Prompt compression** — shorten system prompts and few-shot examples; drop redundant
  instructions. (Aggressive "CRITICAL: YOU MUST" scaffolding both wastes tokens *and*
  over-triggers modern models — [Module 2, lesson 02](../part-02-prompt-engineering/02-prompting-reasoning-models.md).)

## Batch APIs — ~50% off for async work

If you don't need the answer *right now*, submit it asynchronously for **~50% off both input
and output** (OpenAI, Anthropic, and Google all offer this; results typically within an hour,
guaranteed within 24h, on a separate rate-limit pool).

| Good fit (batch it) | Wrong fit (don't) |
|---|---|
| Evals, bulk classification/extraction | Interactive chat |
| Embedding generation, dataset labeling | Anything user-facing in real time |
| Overnight reports, content generation | Agent loops needing the result to continue |

The discount **stacks with prompt caching** ([lesson 02](02-caching.md)) — a shared cached
prefix across batch requests. For any non-interactive workload, the batch API is the most
straightforward 2× cost cut available.

## The mental model

Every token is a line item paid on every call. Spend them where they buy quality (a good
system prompt, the right retrieved chunks) and cut them everywhere else (verbose output,
stale history, redundant instructions, real-time billing for work that could be batched).

---

## Next

→ [Caching](02-caching.md) — how to stop paying for the *same* tokens twice.
