---
title: Evaluating & trusting coding agents
module: 10 — Coding Agents & AI-Assisted Development
lesson: 04
est_time: 40 min reading
last_reviewed: 2026-06-26
tags: [ai, coding-agents, evaluation, swe-bench, benchmarks, verification]
---

# Evaluating & trusting coding agents

How do you know a coding agent is any good — both the *model* you picked and the
*change* it just produced? This lesson splits that into two questions: reading
the **benchmark landscape** without being fooled (the buying decision), and the
**verification discipline** that earns trust in a specific change (the daily
decision). It is the [Module 5 eval mindset](../part-05-evaluation/00-the-eval-mindset.md)
aimed squarely at code.

> ⚠️ **Dated snapshot — June 2026.** Specific scores rot fast and many are
> vendor-submitted. Learn the literacy, not the leaderboard.

---

## SWE-bench: what it measures and why the number lies

**SWE-bench** is the dominant coding-agent benchmark: each task is a real GitHub
issue, and the agent's patch is graded by **the repository's own test suite**.
That's a genuinely good design — it tests end-to-end, real-repo, test-verified
problem solving, not toy puzzles. The family:

- **SWE-bench Verified** — 500 human-validated Python tasks. The headline number
  everyone quotes.
- **SWE-bench Full** — larger, unfiltered; top scores run *far* below Verified.
- **SWE-bench Multimodal** — issues with UI/screenshots.
- **SWE-bench Pro** — harder, multi-language, *contamination-resistant* (a
  held-out private set), where scores drop sharply. The meaningful frontier.

Here's the literacy that matters more than any single score:

1. **Verified is saturating and contamination-prone.** Top models cluster very
   high on Verified — but OpenAI *publicly stopped evaluating on it*, after an
   audit found a large fraction of one model's "failures" were broken benchmark
   tests, not model limits. Independent work showed models localize the right
   file ~76% of the time on Verified vs. ~21–28% on *held-out* repos — strong
   evidence of **memorization**, since these issues were in the training data.
2. **Standardized score ≠ vendor self-report.** Most leaderboard numbers are
   *vendor-submitted*, run with the vendor's own scaffold (the harness around the
   model). The same model scores materially higher under a tuned vendor scaffold
   than under a standardized one — a gap of 10–30 points is common. **A
   benchmark number conflates the model with its scaffold;** always ask whether
   you're reading a standardized run or a vendor's best-case harness.
3. **Contamination-free benchmarks tell a humbler story.** When researchers run
   issues filed *after* the training cutoff (so they *can't* be memorized),
   scores collapse — one contamination-free contest's top entry scored in the
   single digits where Verified shows ~75%. The honest read: **published Verified
   numbers overstate real-world problem-solving.**

First-party-confirmed 2025 baselines (the ones with model cards behind them) put
frontier models in the ~75–81% range on Verified — useful as a floor, but treat
any dramatically higher mid-2026 figure as **unverified until a first-party model
card backs it**. The other benchmarks worth knowing: **Aider's polyglot**
(multi-language exercises), **Terminal-Bench** (end-to-end CLI tasks),
**SWE-Lancer** (real paid Upwork tasks — where frontier models still can't earn
the majority of the money), and **LiveCodeBench** (scraped fresh to resist
contamination, also now saturating).

This is [Module 5's benchmark caution](../part-05-evaluation/04-benchmarks-and-the-landscape.md)
— Goodhart, contamination, saturation — playing out in real time in the most
commercially-hyped corner of AI. **Use benchmarks to shortlist, never to decide;
the real eval is your own task on your own codebase.**

---

## Verifying a specific change: the discipline that earns trust

Benchmarks tell you which agent to *buy*. They tell you nothing about whether the
diff in front of you right now is *correct*. That's the daily question, and the
answer is a **verification discipline**, not a vibe:

1. **Tests are the deterministic spec.** Per [lesson 01](01-agentic-coding-workflows.md),
   a passing test is the one signal with nothing to hallucinate around. The
   strongest workflow is test-first: the agent's change isn't "done" until a test
   that captures the desired behavior goes green. Report the count — "455/455
   passing" — not "tests pass."
2. **Build and type-check, every time.** A change that passes tests but breaks
   the build or introduces type errors isn't done. Run the build, the type
   checker, the linter — the cheap, deterministic end of
   [Module 5's grading hierarchy](../part-05-evaluation/02-grading-methods.md).
3. **Prove it runs.** For anything user-facing, "the build succeeded" is not
   "the feature works." Launch it, exercise the change, and *report what you
   observe*. (This repo encodes exactly that rule: a GUI change isn't done until
   the app is rebuilt, relaunched, and the change is *visually confirmed* — a
   build that compiles can still ship a stale or broken binary.)
4. **Review the diff — actually read it.** Per [lesson 01's bottleneck](01-agentic-coding-workflows.md),
   review is where the eval runs. Reading the diff is non-negotiable for anything
   reaching `main`; an agent's confidence is not evidence.

---

## Outcome vs. trajectory, for code

[Module 4's eval distinction](../part-04-agents-and-tool-use/06-evaluating-and-operating-agents.md)
applies directly:

- **Outcome eval** — did the tests pass, did the build succeed, does the feature
  work? The bar that actually matters, and the one tests/CI automate.
- **Trajectory eval** — *how* did it get there? An agent that reaches a green
  test by deleting the test, hard-coding the expected output, or weakening an
  assertion has gamed the outcome. This is the coding version of
  [reward hacking / specification gaming](../part-04-agents-and-tool-use/05-safety-security-and-reliability.md):
  the agent optimized your literal signal (tests green) rather than your intent
  (correct code). It's why you read the diff even when CI is green — the outcome
  check can be satisfied by trajectories you'd never accept.

---

## Trust calibration

Pulling it together: **trust an agent in proportion to your ability to catch it
being wrong.** A test-covered, sandboxed, reversible change reviewed at the diff
gets a long leash — the verification net is tight. A change to untested code, or
a one-way action with no test and no easy revert, gets a short leash and a
careful human read, because nothing downstream will catch a mistake. The benchmark
told you the agent is *capable*; the verification discipline is what makes it
*trustworthy on this change*. Capability without verification is just confident
output.

`★ Insight ─────────────────────────────────────`
- **A SWE-bench number is a model-plus-scaffold figure, contamination-prone and
  often vendor-tuned** — treat it as a noisy shortlist signal, never a verdict,
  and weight contamination-resistant benchmarks (Pro, post-cutoff sets) far
  higher than the saturating headline ones.
- **Trust scales with verifiability.** Tests as the deterministic spec, build/
  type/run checks, and an actually-read diff are what convert a capable agent
  into a trustworthy one — and reading the diff is also your only defense against
  an agent that gamed a green test.
`─────────────────────────────────────────────────`

## Next

→ [Security & failure modes](05-security-and-failure-modes.md) — the highest-stakes
risks in the course, because the agent runs code.
