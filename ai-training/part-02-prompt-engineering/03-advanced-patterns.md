---
title: Advanced patterns
module: 02 — Prompt Engineering
lesson: 03
est_time: 35 min reading
last_reviewed: 2026-06-18
tags: [ai, prompting, patterns, chaining, react, meta-prompting]
---

# Advanced patterns

The named techniques from the research canon — what each is, when it earns its keep,
and (crucially) **which ones reasoning models made redundant.** Many of these are the
*manual* version of something the model now does internally; the value today is mostly
in **inspectability and control**, not raw capability.

> Reality check from [lesson 02](02-prompting-reasoning-models.md): on a reasoning model,
> reach for the *simplest* thing first. Most of the patterns below were invented to coax
> reasoning out of models that didn't have it. Use them when you need to *see* or *control*
> the steps — not by default.

## Chain-of-thought (CoT) and its variants

- **Few-shot CoT** — examples that include the reasoning, not just the answer
  ([Wei et al. 2022, arXiv:2201.11903](https://arxiv.org/abs/2201.11903)).
- **Zero-shot CoT** — the "let's think step by step" trigger
  ([Kojima et al. 2022, arXiv:2205.11916](https://arxiv.org/abs/2205.11916)).
- **When:** multi-step problems on **non-reasoning** models (or thinking disabled).
- ⚠️ **On reasoning models: skip it** — redundant or harmful (see lesson 02). If you want
  the model to demonstrate a *style* of reasoning, put `<thinking>`-tagged exemplars in
  your few-shot block and let it generalize the pattern.

## Self-consistency

Sample several independent reasoning paths and **majority-vote** the answer
([Wang et al. 2022, arXiv:2203.11171](https://arxiv.org/abs/2203.11171)). Improves
accuracy on problems with a single correct answer.

- ⚠️ Reasoning models do an internal analogue (explore + backtrack), so manual voting is
  largely redundant — but a best-of-N + verifier pass is still a legitimate **reliability**
  tactic for high-stakes outputs.

## Prompt chaining / decomposition

Break a task into a **pipeline of prompts**, each consuming the last one's output.

- **Why, in 2026:** not because the model can't hold the whole task — it usually can — but
  for **inspectability** (check/repair an intermediate result), **control** (enforce a
  fixed pipeline), and **cost** (cheap model for easy stages, expensive for hard ones).
- **Self-correction** is the go-to chain Anthropic names: **draft → review against
  criteria → refine**, each as a separate call. A fresh-context reviewer beats
  self-critique in the same turn.
- **Least-to-most** — decompose into ordered subproblems and solve in sequence; helps
  compositional tasks ([Zhou et al. 2022, arXiv:2205.10625](https://arxiv.org/abs/2205.10625)).

## ReAct & tool-use prompting

**ReAct** interleaves **Thought → Action → Observation**: the model reasons, calls a tool,
reads the result, and repeats ([Yao et al. 2022, arXiv:2210.03629](https://arxiv.org/abs/2210.03629)).
It's the foundation of agents.

- Today the loop is mostly handled by the platform's tool/function-calling machinery and
  adaptive thinking — you rarely hand-write "Thought:/Action:" anymore.
- What you *do* still write: **good tool descriptions** (be prescriptive about *when* to
  call each tool — capable models under-reach for tools by default), and **action-oriented
  instructions** ("Change this function…" triggers action; "Can you suggest…" triggers
  talk). Raise `effort` to get more tool use.
- This is a deep topic of its own → the planned **Agents & Tool Use** module
  ([CURRICULUM](../CURRICULUM.md)). Treat this as the prompting-layer preview.

## Meta-prompting (let the model improve the prompt)

Ask the model to critique and rewrite an underperforming prompt, or generate prompt
variants to test. Capable models are "highly receptive to metaprompting" (OpenAI). The
research lineage automates this — **APE** ([arXiv:2211.01910](https://arxiv.org/abs/2211.01910)),
**OPRO** ([arXiv:2309.03409](https://arxiv.org/abs/2309.03409)), and **DSPy**
([arXiv:2310.03714](https://arxiv.org/abs/2310.03714)) optimize prompts against a metric
rather than by hand. **When:** you have an eval set (lesson 04) and want to tune
systematically instead of guessing.

## Other canon (know them, reach rarely)

- **Generated knowledge** — have the model list relevant facts first, then answer using
  them ([arXiv:2110.08387](https://arxiv.org/abs/2110.08387)). Largely subsumed by
  built-in reasoning + RAG.
- **Tree of Thoughts** — explore a tree of partial solutions with self-evaluation and
  backtracking ([arXiv:2305.10601](https://arxiv.org/abs/2305.10601)). For search-shaped
  problems; heavy, and mostly internalized by reasoning models.

## Templating & variables (and the caching payoff)

Production prompts are **templates** with a stable scaffold and a few injected variables.
Beyond maintainability, structure them with a hard rule in mind:

> **Keep the stable part first, the volatile part last.** This is how **prompt caching**
> works — providers cache a *prefix* match, so a frozen system prompt + frozen tool list
> at the front gets cached and reused, while per-request variables go at the end. A
> timestamp or user ID interpolated into the *system* prompt silently breaks the cache for
> everything after it.

Practical rules:
- Frozen instructions/examples → top (cacheable). Per-request data/question → bottom.
- Serialize any injected JSON deterministically (sorted keys) so the prefix bytes don't
  change.
- This dovetails with the long-context layout from [lesson 01](01-core-techniques.md)
  (long data near the top, question at the end) — same principle, two payoffs (quality +
  cache hits).

## Which pattern, when

| Pattern | Use it for | On reasoning models |
|---|---|---|
| Few-shot CoT | Multi-step tasks, non-reasoning models | Skip — built in |
| Self-consistency | Single-answer accuracy, high stakes | Mostly redundant; best-of-N + verify still useful |
| Prompt chaining | Inspectability, pipeline control, cost tiering | Still valuable (control, not capability) |
| Self-correction | Quality on hard outputs | Valuable; use a fresh-context reviewer |
| ReAct / tool prompting | Anything that calls tools | Handled by tool-calling; write good tool descriptions |
| Meta-prompting | Systematic prompt tuning (with an eval set) | Valuable |
| Templating + caching | Every production prompt | Always |

---

## Next

→ [Reliability, security & evaluation](04-reliability-security-and-evaluation.md) — making
prompts trustworthy, hard to hijack, and measurable.
