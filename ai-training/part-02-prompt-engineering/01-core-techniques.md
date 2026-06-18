---
title: Core techniques
module: 02 — Prompt Engineering
lesson: 01
est_time: 35 min reading
last_reviewed: 2026-06-18
tags: [ai, prompting, techniques, few-shot, structured-output, long-context]
---

# Core techniques

The workhorse techniques, roughly in the order you'd reach for them. Each says **what
it is, when to use it, and the 2026 caveat** (several of these behave differently on
reasoning models — flagged, with the full story in
[lesson 02](02-prompting-reasoning-models.md)).

## Zero-shot — the baseline

Just ask, no examples. For a well-specified task this is the right starting point, and
on reasoning models it's often the *best* point (examples can hurt — see below). Write
the clearest possible instruction first; only add machinery if a test shows you need it.

## Few-shot / in-context learning

Give the model a handful of input→output examples so it infers the pattern.

- **How many:** 3–5 is the usual sweet spot.
- **Make them relevant *and* diverse** — diversity stops the model latching onto an
  accidental pattern (e.g. all your examples being short, so it never goes long).
- **Delimit them** — wrap each in `<example>` tags (or similar) so they're clearly
  examples, not instructions.
- **Best for:** enforcing a specific output format/tone/structure, niche tasks, edge-case
  handling.
- ⚠️ **2026 caveat:** on **reasoning models, few-shot often *hurts*** — OpenAI says to
  "try to write prompts without examples first," and misaligned examples degrade results.
  Use zero-shot first on reasoning models; reserve few-shot for non-reasoning models or
  for pinning an exact output shape. [(OpenAI reasoning best practices)](https://developers.openai.com/api/docs/guides/reasoning-best-practices)
  Note the divergence: Google still recommends "**always**" including few-shot examples
  for its *general* (non-thinking-heavy) Gemini usage — so this is provider/model-specific,
  not universal law.

## System prompts & roles

Put durable, app-level instructions in the **system** channel (OpenAI now calls this the
**`developer`** role; it outranks the user message). Even one sentence of role focus
helps: `"You are a senior Python reviewer."`

- **Use roles for voice, tone, format, and ground rules.**
- ⚠️ **Personas don't reliably improve *accuracy*.** Multiple studies (2023–2025) found
  expert personas ("You are a world-class mathematician") don't make answers more
  correct. Use a persona to steer *style*, not as a correctness lever.

## Delimiters & XML tags

Mark the boundaries between instructions, context, examples, and data. This is the
highest-leverage structural habit:

- **Claude is specifically tuned for XML tags** — wrap each content type in its own
  descriptive tag (`<instructions>`, `<context>`, `<document>`), nest for hierarchy,
  and reuse the tag name when you refer back to it.
- Markdown headers and fenced code blocks work too (OpenAI/Gemini lean on these).
- Tags double as **output controls**: *"Put the prose in `<summary>` tags and the risks
  in `<risks>` tags."*
- And they're a **security boundary** — clearly-delimited, labeled-untrusted data is
  harder to hijack via injection ([lesson 04](04-reliability-security-and-evaluation.md)).

## Structured / JSON output

When a program will consume the output, don't just write *"respond in JSON"* and hope.

- **Prefer the platform's native structured-output feature** — OpenAI Structured Outputs
  (`strict: true`), Anthropic Structured Outputs (`output_config.format` with a JSON
  schema), Gemini's response schema. These *constrain* generation to valid schema-
  conforming output, rather than relying on the model's goodwill.
- Anthropic now explicitly recommends Structured Outputs **over the old prefill trick**
  for forcing JSON.
- Prompt-only JSON ("respond with a JSON object with keys x, y") is the fallback when no
  native feature is available — and you must then validate + retry.

## Output formatting & length control

- **Say what to do, not what to avoid** (*"write flowing prose"* > *"no bullets"*).
- **Match your prompt's style to the desired output** — a markdown-heavy prompt nudges
  markdown-heavy output; strip markdown from the prompt to get cleaner prose.
- **Length is increasingly a parameter, not a sentence** — GPT-5 family exposes
  `text.verbosity` (low/medium/high) separate from reasoning depth; modern models also
  honor explicit caps ("3–6 sentences," "≤ 5 bullets"). Newer models default *terser* and
  calibrate length to perceived complexity, so state a fixed length if you need one.
- **Math formatting:** Claude 4 defaults to LaTeX; ask for plain text explicitly if you
  don't want `$…$` / `\frac{}{}`.

## Long-context prompting (20k+ token inputs)

When you stuff a long document or codebase into the prompt:

- **Put the long data near the top, the question at the end.** Both Anthropic and Google
  converge here: Anthropic reports queries-at-the-end can improve quality by up to ~30%
  on complex multi-document inputs; Gemini's guide says to "put your query at the end…
  after all the other context."
- **Wrap each document** in `<document>` with `<document_content>` and `<source>` subtags
  so the model can reference and cite them.
- **Ground with quotes** — ask the model to first extract relevant verbatim quotes (into
  `<quotes>` tags), then answer using only those. Cuts noise and curbs hallucination.
- ⚠️ **Multi-needle weakness (Gemini, and a general caution):** long-context retrieval is
  strong for a *single* fact but less reliable when you need *several* specific facts
  scattered across a huge input. For heavy retrieval, prefer RAG over brute-force
  long-context. [(Gemini long-context)](https://ai.google.dev/gemini-api/docs/long-context)
- For repeated queries over the same big corpus, use **context/prompt caching** to cut
  cost and latency (see [lesson 03](03-advanced-patterns.md) on templating + caching).

## Prefilling — and why it's increasingly gone

"Prefilling" = putting words in the model's mouth by starting the assistant turn for it
(e.g. opening `{` to force JSON, or `"Here is the summary:"` to skip preamble).

- ⚠️ **On the newest Claude models (4.6 and later), prefilling the last assistant turn is
  unsupported and returns an error.** Replacements: use **Structured Outputs** for
  format-forcing; a **system instruction** ("respond directly, no preamble") for preamble
  removal; move a continuation into a **user** message.
- It still works on **older** models, and assistant messages *elsewhere* in the
  conversation (few-shot examples) are unaffected — so "prefill is dead" is an
  over-generalization. But for new work, reach for structured outputs instead.

## Quick reference — technique → when

| Technique | Reach for it when… | Reasoning-model caveat |
|---|---|---|
| Zero-shot | Task is well-specified | **Preferred** baseline |
| Few-shot | Need an exact format/tone, niche task | Often **hurts** — try zero-shot first |
| Role/system | Set voice, rules, expertise | Fine; not an accuracy lever |
| Delimiters/XML | Always, once there's data + instructions | Always good |
| Structured output | A program parses the result | Always good (use native feature) |
| Long-context layout | 20k+ token inputs | Use RAG for multi-fact retrieval |
| Prefill | Older models only | Removed on Claude 4.6+ → use structured outputs |

---

## Next

→ [Prompting in the reasoning era](02-prompting-reasoning-models.md) — what changes once
the model thinks for itself.
