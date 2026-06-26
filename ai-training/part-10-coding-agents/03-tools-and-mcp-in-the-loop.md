---
title: Tools & MCP in the coding loop
module: 10 — Coding Agents & AI-Assisted Development
lesson: 03
est_time: 35 min reading
last_reviewed: 2026-06-26
tags: [ai, coding-agents, tools, mcp, guardrails]
---

# Tools & MCP in the coding loop

A coding agent *is* its tools. The model decides what to do; the tools are how it
actually reads, writes, runs, and reaches the outside world. This lesson covers
the tool surface of a coding agent, how **MCP** extends it, and — most
importantly — how to **guardrail the dangerous ones**. It's the
[Module 4 tool/function-calling](../part-04-agents-and-tool-use/01-tool-and-function-calling.md)
and [MCP](../part-04-agents-and-tool-use/04-mcp-and-the-tool-ecosystem.md)
material grounded in the dev loop.

---

## The built-in tool surface

A capable coding agent ships a small, well-designed set of built-in tools. The
durable categories (names vary by tool; Claude Code's set is illustrative):

- **File ops** — `Read` (files, images, PDFs, notebooks), `Edit` (exact string
  replacement — read before you edit), `Write` (create/overwrite), `Glob`
  (find by pattern).
- **Search & code intelligence** — `Grep` (regex over file contents, ripgrep-
  backed), and increasingly an `LSP`/language-server tool for jump-to-definition,
  find-references, and type errors. The language server matters: it turns
  "search for the string `foo`" into "find the actual *symbol* `foo`," which is
  the difference between an agent that understands code and one that pattern-
  matches text.
- **Execution** — `Bash` (run shell commands; the universal escape hatch),
  often with a background mode for long-running processes you don't want to
  block on.
- **Web** — `WebSearch` / `WebFetch` for docs and current information past the
  model's cutoff (the [Module 4 server-tool](../part-04-agents-and-tool-use/01-tool-and-function-calling.md)
  pattern).
- **Orchestration** — spawning subagents, running skills, managing background
  tasks ([lesson 02](02-context-and-orchestration.md)).

The [Module 4 tool-design](../part-04-agents-and-tool-use/01-tool-and-function-calling.md)
principle holds: **a dedicated tool beats a bash one-liner when the harness needs
to gate, render, audit, or parallelize the action.** A dedicated `edit` tool can
enforce "the file hasn't changed since you read it" and show a clean diff; the
same edit done via `bash -c "sed ..."` is an opaque command string the harness
can't inspect. Promote an action to its own tool when you need a security
boundary or a custom UI; use bash for breadth.

---

## MCP in the dev loop

The built-in tools cover the *codebase*. **MCP (Model Context Protocol)**
connects the agent to everything *around* it — the same open standard from
[Module 4](../part-04-agents-and-tool-use/04-mcp-and-the-tool-ecosystem.md),
now the dominant way to give a coding agent project-specific reach:

- **Issue trackers** — read the GitHub issue, Jira ticket, or Linear task the
  work is *about*, so the agent has the actual requirement, not your paraphrase.
- **Databases** — query a dev database to understand the schema before writing a
  migration.
- **Version control & PRs** — open a PR, read review comments, push a branch.
- **Design & docs** — pull a spec from Drive, a design from Figma.
- **Observability** — read logs or a dashboard to debug a production issue.

This is what turns a tier-(d) background agent into something genuinely
autonomous: "fix issue #421" works because the agent can *read* #421, find the
code, edit it, run the tests, and *open the PR* — each a tool call, several of
them MCP.

### The scaling problem: tool search

Connect a handful of MCP servers and you've added dozens of tool definitions —
each one consuming context on every turn, the
[Module 4 context-rot](../part-04-agents-and-tool-use/03-context-engineering-and-memory.md)
problem. The fix is **tool search** (a [Module 4 pattern](../part-04-agents-and-tool-use/01-tool-and-function-calling.md)):
defer the tool definitions, and let the agent *search* for and load only the
tools it needs for the current task. With many servers connected this is the
difference between a usable agent and one drowning in its own tool catalog.

---

## Guardrails on destructive actions

Here is where coding agents differ from every other agent in this course: **they
run code.** A wrong tool call isn't a bad sentence — it's a deleted file, a
dropped table, a force-pushed branch, a leaked secret. The guardrail layers,
defense-in-depth:

1. **Permission rules (agent-level).** Evaluated as deny → ask → allow. *Deny*
   permanently blocks an action (and removes the tool from the agent's context
   entirely, so it never even tries). *Ask* always prompts. *Allow* auto-approves
   routine safe actions. The pattern: allowlist the safe and reversible
   (`Bash(npm test)`, reads), deny the catastrophic (`Bash(rm -rf /)`), and let
   everything else prompt.
2. **Sandboxing (OS-level).** A leash the agent *cannot* talk its way past,
   because it's enforced by the operating system, not the model. Confine
   filesystem reads/writes to the project directory; restrict network egress to
   an allowlist of domains. Modern coding agents ship this — network off by
   default, filesystem scoped to the working directory — and report it cuts
   permission prompts dramatically because most actions are now provably safe.
   Critically, **sandboxing is the layer that survives prompt injection**
   ([lesson 05](05-security-and-failure-modes.md)): even if the agent is tricked
   into running a malicious command, the OS won't let it reach outside the box.
3. **Checkpoints & version control.** Reversibility as a backstop — undo file
   edits within a session, and (the real safety net) commit often so any agent
   change is a `git revert` away. The
   [Module 4 reversibility criterion](../part-04-agents-and-tool-use/05-safety-security-and-reliability.md):
   the easier an action is to undo, the longer a leash it can run on.
4. **Hooks.** Shell commands that fire at tool-lifecycle events — auto-format
   after every edit, block a command matching a dangerous pattern, run tests
   before a commit, audit-log what the agent did. The deterministic, code-level
   guardrail that doesn't depend on the model behaving.

The durable principle ties straight back to
[lesson 01's leash](01-agentic-coding-workflows.md): **reversible, well-tested
actions get a long leash; one-way doors (migrations, deploys, pushes, deletes)
always prompt — and the whole agent runs inside an OS sandbox so a single bad
call can't escape the box.**

`★ Insight ─────────────────────────────────────`
- **A coding agent is its tools** — and a *language-server* tool (symbols, not
  strings) plus *MCP* (issues, DBs, PRs) is what separates an agent that
  genuinely operates in your project from one that just edits text in a folder.
- **Because the tools run code, guardrails are defense-in-depth, not a setting.**
  Permission rules gate intent, the OS sandbox enforces a boundary injection
  can't cross, and version control makes mistakes reversible — you want all
  three, and the sandbox is the one that holds when the model is fooled.
`─────────────────────────────────────────────────`

## Next

→ [Evaluating & trusting coding agents](04-evaluating-and-trusting-coding-agents.md)
— SWE-bench reality, and the verification discipline that earns trust.
