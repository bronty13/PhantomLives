---
title: Agent fundamentals
module: 04 — Agents & Tool Use
lesson: 00
est_time: 30 min reading
last_reviewed: 2026-06-18
tags: [ai, agents, tool-use, fundamentals]
---

# Agent fundamentals

An **agent** is an LLM that *directs its own process* — deciding what to do next, calling
tools, and using the results to decide the step after that, in a loop, until the task is
done. That autonomy is powerful and expensive, which is why the most important skill in
this module is knowing **when not to build one.**

This module is the capstone of what came before: it builds on tool prompting
([Module 2, lesson 03](../part-02-prompt-engineering/03-advanced-patterns.md)) and agentic
retrieval ([Module 3, lesson 03](../part-03-rag/03-retrieval-quality.md)).

## The complexity ladder

There are three rungs, and they differ by **who controls the flow**:

| Rung | What it is | Who decides the next step |
|---|---|---|
| **Single augmented LLM call** | One call + retrieval/tools/memory | — (one shot) |
| **Workflow** | LLMs + tools orchestrated through **predefined code paths** | **Your code** |
| **Agent** | LLM **dynamically directs its own process** and tool use over many steps | **The model** |

That last distinction is the whole game. In a *workflow* you wrote the sequence; in an
*agent* the model decides the sequence at runtime, using feedback from the environment.
[(Anthropic — Building Effective Agents)](https://www.anthropic.com/engineering/building-effective-agents)

## The augmented LLM (the atomic unit)

Underneath every agent is a single LLM enhanced with three augmentations:

- **Tools** — functions it can call to *act* on the world (APIs, code, files).
- **Retrieval** — fetching external information ([Module 3 — RAG](../part-03-rag/00-rag-fundamentals.md)).
- **Memory** — retaining information across steps and sessions ([lesson 03](03-context-engineering-and-memory.md)).

Get this unit right — clear tools, good retrieval, sensible memory — before you orchestrate
anything on top of it.

## The agent loop

A practical agent runs a simple loop:

```
gather context → take action → verify the work → repeat
```

The non-negotiable part is **verify** — the agent must get *ground truth from the
environment* at each step (a tool result, a test run, a screenshot), not just trust its
own narration of progress. Verification comes in three flavors: **rules-based** (lint,
type-check), **visual** (screenshot a UI), and **LLM-as-judge**. An agent that doesn't
check its work against reality drifts.
[(Building agents with the Claude Agent SDK)](https://claude.com/blog/building-agents-with-the-claude-agent-sdk)

## When to build an agent — the gate

> **The strongest, most repeated guidance in the entire field:** *"find the simplest
> solution possible, and only increase complexity when needed. This might mean not
> building agentic systems at all."* For many applications, a single well-prompted call
> with retrieval and examples is enough. — Anthropic

Agents trade **latency and cost** for **better performance on hard, open-ended tasks**.
Only pay that when the task demands it. Run these four checks first:

| Factor | Build an agent only if… |
|---|---|
| **Complexity** | The task is open-ended and you *can't* predict the steps or hardcode the path |
| **Value** | The outcome is worth the higher cost and latency |
| **Viability** | The model is actually capable of the task reliably |
| **Cost of error** | Mistakes are recoverable / catchable (sandbox, tests, review) — because autonomy *compounds* errors |

If any answer is "no," drop down a rung. The decision tree:

- Predictable steps? → **Workflow** (Anthropic's workflow patterns — [lesson 02](02-agent-architectures-and-patterns.md)).
- Truly open-ended, unpredictable steps, high value, recoverable errors? → **Agent**.
- Neither? → A **single augmented call**.

OpenAI frames the same gate from the other side — build an agent when rule-based code keeps
failing: **complex judgment**, **brittle/ever-changing rules**, or **heavy reliance on
unstructured data**. Skip it when the workflow is deterministic, speed is critical, or
simple conditional logic suffices.

## The tradeoff to keep in mind

Autonomy buys capability but brings **higher cost, higher latency, and compounding errors**
— a 90%-reliable step run ten times in a row is not 90% reliable overall. That's why
agents demand sandboxed testing, guardrails, and evaluation
([lessons 05](05-safety-security-and-reliability.md)–[06](06-evaluating-and-operating-agents.md))
in a way single calls never did. Start simple; earn each rung of complexity.

---

## Next

→ [Tool & function calling](01-tool-and-function-calling.md)
