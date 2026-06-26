---
title: Agentic coding workflows
module: 10 — Coding Agents & AI-Assisted Development
lesson: 01
est_time: 40 min reading
last_reviewed: 2026-06-26
tags: [ai, coding-agents, workflow, plan-act-verify, spec-driven]
---

# Agentic coding workflows

A coding agent's *capability* is set by the model; its *usefulness* is set by the
**workflow you run it in**. This lesson is the durable core of the module — the
loop and the practices that make agentic coding productive rather than a slot
machine. These age slowly even as the tools churn.

---

## The plan → act → verify loop

Every effective coding agent runs the same loop, and it's the same one from
[Module 4](../part-04-agents-and-tool-use/00-agent-fundamentals.md) with code as
the environment:

1. **Gather context** — read the relevant files, the build config, existing
   patterns; search the codebase; probe the environment.
2. **Take action** — edit files, create files, run commands.
3. **Verify results** — run the tests, check the build, execute the changed
   code; if it fails, loop back.

The loop repeats — often dozens of times for a real task — course-correcting as
new information appears. Two durable principles make it work:

- **Explore before implementing.** Separating *research* from *editing*
  reliably beats jumping straight to code. A model that first reads the
  surrounding code and proposes an approach makes fewer wrong turns than one that
  starts editing on turn one. This is why agents expose a **plan mode** — a phase
  that explores and proposes *without touching your files*. In Claude Code, plan
  mode is one of the permission modes (cycle with `Shift+Tab`); the agent
  analyzes, proposes, you refine, then it implements.
- **Stay in the loop.** You can interrupt at any time to steer, add context, or
  redirect. The loop is human-interruptible by design — an agent on a long task
  is a collaborator you can correct, not a batch job you fire and forget.

---

## Spec-driven development

The 2025–26 maturation of agentic coding is **spec-driven development**: instead
of one prose prompt, you have the agent produce gated artifacts *before* it
writes code. The pattern (AWS Kiro, GitHub's open-source Spec Kit, and others):

```
requirements  →  design / plan  →  task breakdown  →  implement
   (what)          (how)            (steps)            (do it)
```

- **Kiro** generates `requirements.md` → `design.md` → `tasks.md`, with the
  human gating each artifact, and groups independent tasks into concurrent
  "waves."
- **GitHub Spec Kit** uses slash-commands `/specify → /plan → /tasks →`
  implement, positioned explicitly as "the antidote to vibe-coding."

Why it works: it front-loads the *decisions* into reviewable text where they're
cheap to change, instead of discovering them as bugs in generated code where
they're expensive. It's the same instinct as
[Module 2's structured prompting](../part-02-prompt-engineering/01-core-techniques.md)
and [Module 4's plan-then-execute](../part-04-agents-and-tool-use/02-agent-architectures-and-patterns.md),
scaled to a whole feature. The durable lesson is not any one tool's slash
commands — it's **make the agent commit to a reviewable plan before it writes a
line.**

---

## Test-first agent loops

A passing/failing test is a **deterministic signal** — there's nothing for the
model to hallucinate around. That makes test-first the highest-leverage workflow
in agentic coding:

1. Have the agent (or you) write a **failing test** that captures the desired
   behavior.
2. Let the agent implement until the test passes.
3. The test is now both the spec *and* the verification.

This closes the [Module 4 evaluation gap](../part-04-agents-and-tool-use/06-evaluating-and-operating-agents.md):
"did the agent succeed?" becomes a concrete, automatable check rather than a
judgment call. The most capable 2026 terminal agents run tests *inside* their
own loop — "loop engineering" — so they self-correct against the test signal
before ever handing you the result.

---

## Diff review is the new bottleneck

Here is the most important *operational* fact about agentic coding in 2026: the
constraint moved from **writing** code to **reviewing** it. When an agent can
produce a hundred lines of plausible change in seconds, the scarce resource is
human attention to verify it's *correct*.

Industry reports through 2026 (directional, not first-party-precise) tell a
consistent story: teams ship more tasks and open far more PRs, but **PR review
time and merge latency rise sharply** — and on some measures main-branch
throughput *fell* even as feature-branch activity soared. More code generated
does not mean more *value* shipped if it bottlenecks at review.

The durable mitigation is the **"review sandwich"**: a human-set spec at the
front (the plan), the agent's work in the middle, and a deliberate human review
at the end — never letting agent-generated code reach `main` without a real read.
This is the [Module 5 eval discipline](../part-05-evaluation/00-the-eval-mindset.md)
relocated into your git workflow: **the diff is the eval, and review is where it
runs.**

---

## Keeping the agent on a leash

The autonomy ladder from [lesson 00](00-the-coding-agent-landscape.md) is a
*runtime* dial, not just a product category. Mature agents let you move up and
down it per task:

- **Permission modes.** Claude Code cycles default (prompts before edits/commands)
  → auto-accept edits → plan (explore only) and exposes a research-preview "auto"
  mode with background safety checks — switched live with `Shift+Tab`.
- **Allowlists.** Pre-approve safe commands (`Bash(npm test)`, reads under the
  project) in settings so the agent doesn't stop to ask for routine actions,
  while side-effecting actions still prompt.
- **Checkpoints.** Every file edit is reversible within a session (separate from
  git) — you can rewind if the agent went the wrong way.

The durable rule: **tighten the leash for unfamiliar or destructive work, loosen
it for well-tested, reversible loops.** A test-covered refactor can run on a long
leash; a one-way action (a migration, a deploy, a `git push`) should always
prompt. This is [Module 4's least-privilege / human-in-the-loop](../part-04-agents-and-tool-use/05-safety-security-and-reliability.md)
guidance with a concrete UI.

`★ Insight ─────────────────────────────────────`
- **Plan → act → verify, with "explore before implementing" and "tests as the
  signal," is the whole durable workflow.** Tools rename the buttons; the loop
  doesn't change.
- **Review is the bottleneck now, not writing.** The skill of 2026 agentic
  coding is less "prompt well" and more "verify fast and refuse to merge what you
  haven't read" — the review sandwich is the discipline that keeps generated
  volume from becoming generated debt.
`─────────────────────────────────────────────────`

## Next

→ [Context & orchestration for code](02-context-and-orchestration.md) — steering
files, subagents, and parallel work.
