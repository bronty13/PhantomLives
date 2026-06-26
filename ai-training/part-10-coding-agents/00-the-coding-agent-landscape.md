---
title: The coding-agent landscape & when to use one
module: 10 — Coding Agents & AI-Assisted Development
lesson: 00
est_time: 35 min reading
last_reviewed: 2026-06-26
tags: [ai, coding-agents, autonomy, tools, landscape]
---

# The coding-agent landscape & when to use one

Modules 1–9 built up the general theory of choosing, prompting, orchestrating,
and evaluating models. This module narrows to the single application where most
practitioners actually *live* day to day: **AI-assisted software development**.
It's also the area that moved fastest in 2025–26 — so, true to the course, we
lead with the durable mental model and treat the tool catalog as a dated
snapshot.

> ⚠️ **Dated snapshot — June 2026.** Tools, prices, and ownership in this space
> change weekly (several below changed *ownership* in the past year). Learn the
> framework; re-verify the catalog at the provider links.

---

## The durable model: the autonomy ladder

Every AI coding tool sits somewhere on one spectrum, and the spectrum is defined
by **how much of the loop the human still holds**:

| Tier | Name | The human… | The tool… |
|---|---|---|---|
| **(a)** | Autocomplete / inline completion | writes code, accepts/rejects keystroke-by-keystroke | predicts the next line(s) in-editor |
| **(b)** | AI chat in the IDE | asks, pastes context | answers in a side panel, proposes edits you apply |
| **(c)** | Interactive agent (human-in-loop) | gives a task, approves edits/commands, steers | edits across the repo live, runs tests, iterates — but **pauses for permission** |
| **(d)** | Autonomous / background agent | files a task (often a GitHub issue), reviews the PR | works async in a sandbox, plans/edits/tests, **opens a PR** with little supervision |

The single most important framing: **the ladder is a leash, not a quality
ranking.** Higher tiers don't mean "better" — they trade *oversight for
throughput*. Tier (a) gives you total control and zero leverage on a big task;
tier (d) gives you a finished PR but you reviewed none of the intermediate
steps. The practitioner's actual skill is **matching the tier to the task's
risk and your ability to verify the result** — which is exactly the
[Module 4 agent-vs-workflow](../part-04-agents-and-tool-use/00-agent-fundamentals.md)
decision, applied to code.

By 2026 nearly every major tool *spans* tiers (b)–(d): "a background agent that
opens a PR" became table stakes. Pure-tier-(a) tools are now the exception.

---

## The tool map (June 2026 snapshot)

Tools mapped to where they sit, with what's distinctive. *Re-verify pricing and
ownership at each vendor's site — this churns.*

| Tool | Tiers | Distinctive | Notes |
|---|---|---|---|
| **Claude Code** (Anthropic) | (c)(d) | terminal-first interactive + background; the $100/mo "power tier" benchmark | the subject of [lessons 01–05](01-agentic-coding-workflows.md) |
| **GitHub Copilot** | (a)–(d) | inline + chat + agent mode + issue→PR coding agent | moved to usage-based "AI Credits" billing June 2026 |
| **Cursor** (Anysphere) | (a)–(d) | AI-native editor; parallel "Agents Window"; own Composer model | Cursor 3 "Glass" shipped Apr 2026 |
| **Windsurf** | (a)–(d) | AI-native editor | **now owned by Cognition** (Devin's maker) |
| **OpenAI Codex / Codex CLI** | (b)–(d) | CLI + cloud + IDE agentic suite (not the 2021 model) | token billing + Pro 5× tier added 2026 |
| **Google Antigravity + Jules** | (a)–(d) | agentic platform with a "Manager Surface" for async agents; Jules opens PRs | Gemini Code Assist (individual) folded into Antigravity |
| **Devin** (Cognition) | (d) | flagship autonomous SWE-agent; Interactive Planning + confidence score | |
| **AWS Kiro** | (c)(d) | built around **spec-driven development** | successor to Amazon Q Developer (being EOL'd) |
| **Aider** | (c) | open-source CLI agent + its own polyglot benchmark | |
| **Zed / Cline / Continue** | (a)–(c) | open-source editors/agents | |

Two cross-cutting themes worth telling a reader:
- **2025–26 was a consolidation year.** Windsurf → Cognition, Amazon Q → Kiro,
  Gemini Code Assist (individual) → Antigravity, Sourcegraph Cody → Amp. Don't
  over-anchor on any one product name.
- **Billing converged on token/usage-based** (Copilot Credits, Cursor, Codex,
  Replit "effort") because agentic tasks burn *far* more tokens than chat — a
  direct consequence of [Module 7's token economics](../part-07-cost-and-latency/01-token-economics.md).

---

## When a plain LLM call beats an agent

This module is about coding agents, but the **[Module 4 "when not to build one"
gate](../part-04-agents-and-tool-use/00-agent-fundamentals.md)** applies hard
here. Reach *down* the ladder when:

- **The task is small and fully specifiable.** "Rename this variable
  everywhere," "add a docstring to this function" — tier (a)/(b) or even a plain
  one-shot completion does it faster, cheaper, and with no risk of an agent
  wandering. An agent is overkill for a one-line change.
- **You can't verify the result.** Tier (d) only makes sense when there's a
  *test suite, a CI gate, or a review* that catches a wrong answer. Letting an
  autonomous agent open PRs against code you can't evaluate is how silent bugs
  ship. (This is the "cost of error" criterion from Module 4, made literal.)
- **A deterministic tool is exact.** Codemods (`jscodeshift`, `gofmt`,
  `rust-analyzer` rename) do mechanical refactors *exactly* and for free — don't
  pay a probabilistic model to do what an AST transform does deterministically.

The discipline: **start at the lowest tier that does the job, and climb only
when the task's complexity and your ability to verify both justify it.**

---

## Why this module exists

AI-assisted development is the application that most rewards the rest of this
course. The autonomy ladder is the [model-selection](../part-01-model-landscape/00-how-to-choose-a-model.md)
decision; the agent loops are [Module 4](../part-04-agents-and-tool-use/00-agent-fundamentals.md);
the benchmarks ([lesson 04](04-evaluating-and-trusting-coding-agents.md)) are
[Module 5 eval](../part-05-evaluation/00-the-eval-mindset.md); the token burn is
[Module 7 cost](../part-07-cost-and-latency/00-fundamentals-and-the-triangle.md);
and the prompt-injection risk ([lesson 05](05-security-and-failure-modes.md)) is
[Module 4's lethal trifecta](../part-04-agents-and-tool-use/05-safety-security-and-reliability.md)
with the highest stakes in the whole course, because the agent runs code.

`★ Insight ─────────────────────────────────────`
- **The autonomy ladder is a leash, not a tier list.** Higher autonomy buys
  throughput at the cost of oversight — the skill is matching the tier to how
  badly a wrong answer would hurt and how well you can catch it.
- **The "when not to use an agent" gate is sharper for code than anywhere
  else**, because the downside (a merged bug, an executed destructive command)
  is concrete and sometimes irreversible. Climb the ladder deliberately, never
  by default.
`─────────────────────────────────────────────────`

## Next

→ [Agentic coding workflows](01-agentic-coding-workflows.md) — the plan→act→verify
loop, spec-driven development, and keeping an agent on a leash.
