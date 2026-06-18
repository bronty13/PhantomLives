---
title: Prompting fundamentals
module: 02 — Prompt Engineering
lesson: 00
est_time: 30 min reading
last_reviewed: 2026-06-18
tags: [ai, prompting, fundamentals]
---

# Prompting fundamentals

This is the spine of the module. The durable principles here **survived** the big
reasoning-model shift (covered in [lesson 02](02-prompting-reasoning-models.md)) — they
age slowly. Learn these first; the model-specific knobs come later.

> Prerequisite: [Module 0 vocabulary](../part-00-orientation/00-how-to-use-this-course.md)
> (tokens, context, reasoning models, effort). Prompting and "how hard the model thinks"
> are different levers — this module is about the *words*; effort/thinking is the *dial*.

## What prompt engineering is — and isn't

A **prompt** is everything you put in front of the model: the instruction, the
context, examples, the data, and the requested output shape. **Prompt engineering** is
iterating on that input until the output reliably meets your bar.

It is *not* a magic incantation hunt. Two framing rules from the start:

- **Not every problem is a prompt problem.** If the model lacks the *facts*, you need
  retrieval (RAG), not better wording. If it lacks the *capability*, you need a
  stronger model or fine-tuning. If latency/cost is the issue, change the model or
  effort. Anthropic says this plainly: "latency and cost can sometimes be more easily
  improved by selecting a different model."
  [(overview)](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/overview)
- **Prompting is empirical, not theoretical.** You can't reason your way to the best
  prompt; you test it. Which is why the prerequisites below come *before* you write a
  word.

## The three prerequisites (do these before prompt-engineering)

Anthropic's docs insist on these, and they're right:

1. **Define success** — what does a good output look like? Be specific and measurable
   ("valid JSON with these 4 fields," "≤ 5 bullets," "cites a source for every claim").
2. **Have a way to test it** — even 10–20 example inputs you can eyeball, or an
   automated check. Without this you're guessing. (Full treatment in
   [lesson 04](04-reliability-security-and-evaluation.md).)
3. **Have a first-draft prompt** — you improve a draft; you don't conjure a perfect one.

## The anatomy of a prompt

Most strong prompts have some subset of these parts. Keep each part distinct (see
"separate instructions from data" below):

| Part | What it does | Where it goes |
|---|---|---|
| **Role / system prompt** | Sets persona, expertise, ground rules | System/developer channel, first |
| **Task / instruction** | The actual ask, in the imperative | Near the top |
| **Context / motivation** | *Why*, background, audience | After the task |
| **Examples** | Demonstrations of the desired output | Mid-prompt, clearly delimited |
| **Input data** | The thing to act on (doc, code, ticket) | **Long data → near the top** (see lesson 01) |
| **Output format** | Exact shape: JSON, sections, length | Near the end |
| **Constraints** | Must/never rules, edge-case handling | With the instruction or format |

## The durable principles

These hold across every provider and every model generation.

### 1. Be clear and direct
The golden test (Anthropic's): **show your prompt to a colleague with no context — if
they'd be confused, the model will be too.** Use plain imperatives ("Summarize…,"
"Classify…," "Rewrite…"). Ambiguity is the #1 cause of bad output — and on the newest
models, contradictory or vague instructions are *actively* costly (the model burns
reasoning trying to reconcile them).

### 2. Give context and motivation — explain *why*
Don't just forbid; explain. Anthropic's canonical example: instead of *"NEVER use
ellipses,"* say *"Your response will be read aloud by a text-to-speech engine, so never
use ellipses — it doesn't know how to pronounce them."* The model generalizes correctly
from the reason. Provide the **intent and audience**, not just the literal task.

### 3. Show, don't tell (examples)
A few good examples steer format/tone/structure more reliably than paragraphs of
description. (Big caveat for reasoning models — see [lesson 01](01-core-techniques.md)
and [lesson 02](02-prompting-reasoning-models.md) — but as a principle it's foundational.)

### 4. Separate instructions from data
The model can't reliably tell your *instructions* from the *content it should act on*
unless you mark the boundary. Use delimiters — XML tags (`<document>…</document>`),
fenced blocks, or headers. This is both a clarity win **and** the first line of defense
against prompt injection ([lesson 04](04-reliability-security-and-evaluation.md)).

### 5. Say what TO do, not what NOT to do
Positive instructions outperform negative ones. *"Write in flowing prose paragraphs"*
beats *"don't use bullet points."* When you must constrain, pair the prohibition with
the positive alternative.

### 6. Specify the output format explicitly
If you need JSON, a table, three sections, or a word count — say so, and ideally show
it. For machine-consumed output, prefer the platform's **structured-output** feature
over hoping the model formats correctly (lesson 01).

### 7. Give the model an "out"
Tell it what to do when it *can't* comply — "if the document doesn't contain the answer,
reply `NOT FOUND`." Allowing **"I don't know"** is the single highest-leverage move
against confident hallucination ([lesson 04](04-reliability-security-and-evaluation.md)).

## A starter scaffold

A reliable general-purpose skeleton you can adapt (XML-tag flavor; works across
providers, especially Claude):

```
You are <role: one sentence of relevant expertise>.

<task>
<the imperative ask — one or two sentences>
</task>

<context>
<why this matters, who reads the output, any background>
</context>

<input>
<the data/document/code to act on>
</input>

<output_format>
<exact shape: e.g. "A JSON object with keys: summary (string), risks (array of strings)">
</output_format>

If <failure condition>, respond with <fallback> instead.
```

Start minimal. Add a part only when a test shows you need it — don't pre-load the
scaffold with everything.

## The one big shift to know up front

The biggest change in modern prompting: **with capable/reasoning models, less is
more.** Over-prescribing steps, stacking "CRITICAL: YOU MUST" rules, and manually
forcing chain-of-thought now *degrade* output. You give a clear brief and let the model
reason. That shift is important enough to get its own lesson —
→ [lesson 02: Prompting in the reasoning era](02-prompting-reasoning-models.md).

---

## Next

→ [Core techniques](01-core-techniques.md)
