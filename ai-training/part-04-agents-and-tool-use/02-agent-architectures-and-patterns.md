---
title: Agent architectures & patterns
module: 04 — Agents & Tool Use
lesson: 02
est_time: 35 min reading
last_reviewed: 2026-06-18
tags: [ai, agents, workflows, patterns, multi-agent]
---

# Agent architectures & patterns

Most "agent" problems are best solved by a **workflow** — a fixed, code-orchestrated
pipeline — not a fully autonomous agent. This lesson is the catalog: the workflow
patterns, the autonomous-agent loops, and when to reach for multiple agents. Pick the
*least* autonomous pattern that solves the task.

## Workflows vs. agents (recap)

In a **workflow**, your code controls the sequence; in an **agent**, the model does. The
patterns below run from most-structured (workflow) to least (autonomous agent).
[(Anthropic — Building Effective Agents)](https://www.anthropic.com/engineering/building-effective-agents)

## The workflow patterns

| Pattern | What it is | Use it when |
|---|---|---|
| **Augmented LLM** | One call + tools/retrieval/memory | The default — most tasks |
| **Prompt chaining** | Fixed sequence of steps, each consuming the last (optional code "gates" between) | The task cleanly decomposes into fixed subtasks (outline → draft; generate → translate) |
| **Routing** | Classify the input, send it to a specialized handler | Distinct categories handled better separately (route easy queries to a cheap model, hard ones to a strong one) |
| **Parallelization — sectioning** | Split into independent subtasks run in parallel | Subtasks are genuinely independent (answer + run a safety check simultaneously) |
| **Parallelization — voting** | Run the *same* task several times, aggregate | You want confidence / multiple perspectives (several passes vote on "is this code vulnerable?") |
| **Orchestrator-workers** | A central LLM **dynamically** decomposes the task, delegates to workers, synthesizes | Complex tasks where you **can't predict the subtasks** — they're decided at runtime |
| **Evaluator-optimizer** | One LLM generates, another critiques, loop | Clear eval criteria and iterative refinement adds value (the "reflection" pattern) |

The line between **sectioning** and **orchestrator-workers** is exactly the
workflow/agent line: sectioning's subtasks are fixed in your code; orchestrator-workers'
subtasks are chosen by the model. That dynamism is what makes the latter "agentic."

## Autonomous agents

A true agent starts from a user command, then **plans and operates independently**,
looping (gather → act → verify → repeat from [lesson 00](00-agent-fundamentals.md)) and
returning to the human only when it needs judgment or is done. The crucial requirement,
again: **ground truth from the environment at every step** — tool results, test output —
or the agent hallucinates progress.

### Classic named loops
- **ReAct** (reason + act) — think, call a tool, observe, repeat. The loop under most
  single agents.
- **Plan-and-execute** — make a full plan up front, then execute (re-planning as needed).
  Fewer LLM calls per step than ReAct; good when the plan is knowable.
- **Reflection / self-critique** — the agent (or a second model) critiques and revises its
  own output. This *is* the evaluator-optimizer pattern; a fresh-context critic beats
  same-turn self-critique.

## Multi-agent systems

When one agent isn't enough, an **orchestrator (lead) agent** delegates to **specialized
subagents** that work in parallel, each with its own context window and tools, then the
lead synthesizes their condensed results.
[(Anthropic — multi-agent research system)](https://www.anthropic.com/engineering/multi-agent-research-system)

**When multi-agent wins:** Anthropic's research system (Opus lead + Sonnet subagents) beat
single-agent Opus by **90.2%** on their internal research eval. It works when the task is
**open-ended, heavily parallelizable, exceeds a single context window**, and spans many
tools. Subagents give *separation of concerns* and *context isolation* — each explores
independently and returns a distilled 1–2K-token summary instead of its whole context.

**When multi-agent hurts (just as important):**
- **Cost.** Agents use ~4× the tokens of chat; *multi-agent systems use ~15×.* Only worth
  it when the task value justifies that spend.
- **Shared context / dependencies.** Bad fit when every agent needs the same context or
  steps depend tightly on each other — coordination overhead dominates.
- **Most coding.** Research parallelizes; most coding tasks have fewer truly independent
  subtasks. (A concrete, teachable contrast.)
- **Real-time coordination.** Models still aren't great at delegating to each other on the
  fly; subagents often run synchronously, creating bottlenecks.

**Coordination lessons:** delegate *explicitly* — each subagent needs an objective, an
output format, tool/source guidance, and clear boundaries (vague delegation makes
subagents duplicate work); and **scale effort to complexity** (a fact-find needs 1 agent
and a few calls; deep research, 10+ subagents).

> **Both providers' advice: start with ONE agent.** Add agents only when a single one
> clearly outgrows its job (OpenAI's rule of thumb: more than ~20 tools, or genuinely
> disparate domains). Multi-agent is a scaling tool, not a starting point.

## Choosing — the short version

Single call → workflow (chaining/routing/parallel/orchestrator/evaluator) → single agent →
multi-agent, in that order of preference. Stop at the first rung that reliably solves the
task; every rung up costs latency, tokens, and reliability.

---

## Next

→ [Context engineering & memory](03-context-engineering-and-memory.md)
