---
title: Context engineering & memory
module: 04 — Agents & Tool Use
lesson: 03
est_time: 35 min reading
last_reviewed: 2026-06-18
tags: [ai, agents, context-engineering, memory, compaction]
---

# Context engineering & memory

Agents run for many steps, and every step piles tool results, reasoning, and history into
the context window. Left unmanaged, that window fills with low-signal noise and the agent
degrades. **Context engineering** — curating the right tokens at each step — is the
discipline that keeps long-running agents coherent. It's the agent-scale successor to
prompt engineering.
[(Anthropic — Effective context engineering for AI agents)](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)

## Context is finite — and *degrading*

Two facts drive everything here:

- **Context rot.** As the token count grows, the model's ability to accurately recall any
  given fact *decreases*. (We met this in [Module 3, lesson 04](../part-03-rag/04-generation-and-prompt-assembly.md)
  — same phenomenon.) It's a gradient, not a cliff, but it's real.
- **Finite attention budget.** Every token added depletes a shared budget (transformer
  attention is pairwise/n²). More context is not free, and more is not better.

> **The guiding principle:** find the **smallest set of high-signal tokens** that maximize
> the chance of the outcome you want. Curate ruthlessly; don't hoard.

## The toolkit

Four levers, plus two Claude-platform mechanisms that automate the first two.

### 1. Compaction — summarize and continue
When the conversation nears the window limit, **summarize the history** and start a fresh
context from the summary. Tune for **recall first** (don't lose critical facts), then
precision. The risk: over-aggressive compaction drops subtle-but-critical detail. (Server-
side compaction exists on the Claude platform; see [Module 2, lesson 03](../part-02-prompt-engineering/03-advanced-patterns.md)
for the caching interaction.)

### 2. Context editing — prune stale tool results
Automatically **clear old tool results** (and old thinking blocks) once they're no longer
needed — keep the recent few, drop the rest, replaced by a placeholder. On the Claude
platform this is a server-side feature (a beta with date-stamped version strings — verify
current status); it runs before the prompt reaches the model, so your client keeps the
full history. ⚠️ Clearing **invalidates the cached prefix**, so clear in worthwhile chunks,
not constantly.

### 3. Structured note-taking (agentic memory)
Have the agent **write notes to durable storage outside the context window** — a
`NOTES.md`, a to-do list, a progress log — and read them back later. This is how an agent
survives compaction and resumes across sessions ("write your state down before you run out
of room"). The discipline: *only mark a step complete after end-to-end verification.*

### 4. Subagents for context isolation
Hand a focused subtask to a subagent with a **clean context window**; it burns tens of
thousands of tokens exploring and returns a distilled 1–2K-token summary. The lead agent
keeps a high-level plan; the deep work — and its context cost — stays isolated. (This is
the [lesson 02](02-agent-architectures-and-patterns.md) multi-agent pattern, viewed as a
*context* strategy: "the essence of search is compression.")

## Short-term vs long-term memory

| | Short-term | Long-term |
|---|---|---|
| **Scope** | One task/thread/session | Across sessions |
| **Holds** | Recent messages, current tool results | Durable facts, preferences, project state |
| **Mechanism** | The message window + context editing/compaction | A memory store / files / a database |

Most real agents use **both**: a managed working context, plus a persistent store they
write to and read from.

### The memory tool / files-as-memory
A common pattern (Anthropic ships a **memory tool**, currently beta): the model issues
memory commands (`view`, `create`, `str_replace`, `insert`, `delete`, `rename`) against a
`/memories` directory, but **your application executes them** against storage you control.
Because it's client-side, **you own the security**: validate every path, reject `../` and
encoded traversal, confine writes to the memory root. The model is told to check its memory
first and to *assume it may be interrupted* — so it writes state down proactively.

### Retrieval-as-memory (just-in-time)
Instead of pre-loading everything, give the agent **lightweight references** (file paths,
saved queries, URLs) and let it **load data at runtime** — *progressive disclosure*. This
is RAG ([Module 3](../part-03-rag/00-rag-fundamentals.md)) used as long-term memory, and a
semantic-search-backed memory store is exactly that. The winning pattern is **hybrid**:
load a small stable core up front (an instructions file), retrieve the rest just-in-time.

## Matching technique to horizon

| Task shape | Reach for |
|---|---|
| Long conversational back-and-forth | **Compaction** |
| Long tool-heavy loop filling with stale results | **Context editing** |
| Milestone-driven, multi-session work | **Note-taking / files-as-memory** |
| Parallel exploration that exceeds one window | **Subagents** |
| A big knowledge base the agent dips into | **Retrieval-as-memory** |

The throughline: an agent's context is a **managed resource**, not an append-only log.
Curate it deliberately and the agent stays sharp over long horizons.

---

## Next

→ [MCP & the tool ecosystem](04-mcp-and-the-tool-ecosystem.md)
