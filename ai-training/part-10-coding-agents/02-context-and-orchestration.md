---
title: Context & orchestration for code
module: 10 — Coding Agents & AI-Assisted Development
lesson: 02
est_time: 40 min reading
last_reviewed: 2026-06-26
tags: [ai, coding-agents, context, steering, subagents, orchestration]
---

# Context & orchestration for code

A coding agent is only as good as the context it works from and the way you
divide labor across a large task. This lesson is the
[Module 4 context-engineering and architecture](../part-04-agents-and-tool-use/03-context-engineering-and-memory.md)
material made concrete for code: **steering files** (the durable context), and
**subagents / worktrees** (the durable orchestration).

---

## Steering files: persistent project context

The single highest-leverage thing you can give a coding agent is a **steering
file** — a Markdown document the agent loads at the start of every session that
tells it how *this* project works. Without it, the agent re-derives your build
command, your conventions, and your architecture every session (often wrongly).
With it, that context is free and consistent.

**The emerging cross-tool standard is `AGENTS.md`** — a plain-Markdown,
no-required-schema file, introduced in 2025 and now read by 20+ tools across
tens of thousands of open-source projects. Tool-specific variants coexist:
Claude Code reads **`CLAUDE.md`**, Copilot reads
`.github/copilot-instructions.md`, Cursor reads `.cursor/rules`. (Claude Code
can `@AGENTS.md`-import a shared file so both conventions stay in sync.) The
governance even consolidated — `AGENTS.md` and MCP both sit under a Linux
Foundation umbrella as of late 2025.

What goes in a good steering file (the durable advice, tool-agnostic):

- **Build / test / lint commands** — the exact incantations, so the agent's
  verify step (lesson 01) works first try.
- **Conventions** — naming, formatting, the patterns the codebase already uses.
- **Architecture** — where code lives, how the pieces connect, the decisions a
  newcomer would get wrong.
- **Workflow rules** — release steps, what must never be touched, review
  checklists.

And what to *keep out*: one-off instructions (those belong in the conversation),
giant reference material (path-scope it so it loads only when relevant), and
multi-step procedures (those belong in a *skill* — see
[lesson 03](03-tools-and-mcp-in-the-loop.md)). The durable constraint:
**keep it short.** A bloated steering file costs context on every turn and,
past a point, *lowers* adherence — the model can't follow 800 lines of rules as
faithfully as 150. (This is [Module 4 context rot](../part-04-agents-and-tool-use/03-context-engineering-and-memory.md)
in miniature: more context is not more better.)

> This very repo is a worked example — its `CLAUDE.md` carries the build/test
> commands, release-hygiene rules, and per-subproject conventions that a Claude
> Code session loads on launch.

### Layered scope

Steering files layer, lower overriding higher: an org/global file
(`~/.claude/CLAUDE.md`) for personal preferences across all projects, a
project file checked into version control for team-shared rules, and a local
(`.gitignore`d) file for personal project notes. The same hierarchy you'd design
for any config system — and the reason a team can share conventions while each
developer keeps their own quirks.

Some agents also keep **auto-memory** — notes the *agent* writes for itself as it
learns your corrections and discovers build quirks, loaded at session start.
That's the agent-written counterpart to the human-written steering file (and
exactly the [Module 4 memory pattern](../part-04-agents-and-tool-use/03-context-engineering-and-memory.md)).

---

## Subagents and parallel fan-out

A single agent in a single context window is the wrong tool for a task with many
independent parts. **Subagents** — independent agents with their own fresh
context, their own tool permissions, and a specific job — are the orchestration
primitive, and they buy three things straight from
[Module 4's multi-agent lesson](../part-04-agents-and-tool-use/02-agent-architectures-and-patterns.md):

- **Context isolation.** A research/exploration subagent reads twenty files and
  returns a three-line conclusion; the twenty files never touch the main
  conversation's context. The main agent stays focused.
- **Constraint enforcement.** Give a reviewer subagent read-only tools; it
  *cannot* edit even if it tried. Least privilege by construction.
- **Cost control.** Route a cheap, mechanical subtask to a smaller/faster model
  while the main loop stays on the flagship — the
  [Module 7 routing](../part-07-cost-and-latency/03-model-selection-and-routing.md)
  pattern applied within one task.

The canonical win is **parallel fan-out**: review 50 files, or run a search five
different ways, by spawning N subagents at once and collecting their results —
wall-clock cost is the slowest single agent, not the sum. (You launch
independent subagents in *one* batch so they run concurrently; serial spawning
throws the parallelism away.)

**When *not* to**: for a single-file read or a sequential edit, a subagent is
pure overhead — the spawn cost and the round-trip outweigh any benefit. Fan out
when work is genuinely independent; stay direct when it's sequential. (More
capable models in 2026 actually need a *nudge to delegate*, having been tuned to
under-reach for subagents — the opposite of the over-eager-delegation problem of
a year prior.)

---

## Worktree isolation for parallel edits

Subagents that only *read* can run anywhere. Subagents (or sessions) that *edit*
in parallel will clobber each other's files unless you isolate them. The git
primitive for this is the **worktree** — a separate working directory backed by
the same repository, on its own branch.

Running a parallel agent in its own worktree means it edits an isolated copy of
the tree; nothing it does collides with the main session or with a sibling agent
working a different branch. This is the standard pattern for "have three agents
each take one of these three independent features" — each gets a worktree, works
in isolation, and you review three separate branches. It's also why worktree
isolation is *expensive enough to be opt-in*: a fresh worktree costs disk and
setup time, so you reach for it only when agents genuinely mutate files
concurrently, not for read-only fan-out.

---

## Multi-agent orchestration

Beyond ad-hoc fan-out, the structured end is a **coordinator** delegating to a
roster of specialist agents that communicate — a planner that hands tasks to a
coder and a reviewer, results flowing back. The
[Module 4 caution](../part-04-agents-and-tool-use/02-agent-architectures-and-patterns.md)
applies undiluted: multi-agent adds coordination overhead and failure surface,
and is worth it only when the task genuinely decomposes into independent
workstreams. For most coding work, a single capable agent with good steering and
the occasional read-only subagent beats an elaborate agent team. **Reach for
orchestration when the task is wide (many independent parts), not when it's
merely large.**

`★ Insight ─────────────────────────────────────`
- **The steering file is the cheapest, highest-leverage context investment** —
  and `AGENTS.md` is becoming the portable, cross-tool way to make it once.
  Keep it short; bloat costs context every turn and erodes adherence.
- **Orchestration follows task shape, not size.** Fan out subagents (in
  worktrees, if they edit) for genuinely independent work; stay direct and
  sequential otherwise. Parallelism you don't need is just overhead and risk.
`─────────────────────────────────────────────────`

## Next

→ [Tools & MCP in the coding loop](03-tools-and-mcp-in-the-loop.md) — giving the
agent the right tools, and guardrails on the dangerous ones.
