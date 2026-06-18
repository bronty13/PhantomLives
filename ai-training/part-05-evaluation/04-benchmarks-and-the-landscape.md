---
title: Benchmarks & the landscape
module: 05 — Evaluation
lesson: 04
est_time: 30 min reading
last_reviewed: 2026-06-18
tags: [ai, evaluation, benchmarks, safety, red-teaming]
---

# Benchmarks & the landscape

Public benchmarks are how the field talks about model capability — and how model cards and
leaderboards are built. You need to **read them critically**: what each measures, and why a
high score may mean less than it looks. This lesson also covers **safety evaluation**, which
inverts the usual goals.

> ⚠️ **Don't memorize benchmark scores.** Frontier SOTA shifts weekly, and different
> aggregators report different numbers for the *same* benchmark depending on prompting and
> scaffolding. Learn what each benchmark *measures* and its failure modes; look up current
> numbers when you actually need them.

## What the major benchmarks measure

| Category | Benchmarks | Measures | 2026 state |
|---|---|---|---|
| **Knowledge / reasoning** | MMLU / MMLU-Pro, GPQA (Diamond), Humanity's Last Exam (HLE) | Academic & expert-level Q&A | MMLU/GPQA largely **saturated**; **HLE** is the current frontier discriminator |
| **Math** | MATH, AIME, FrontierMath | Competition → research math | MATH/AIME saturating + contamination-prone (labs rotate to the newest AIME year); **FrontierMath** still hard |
| **Coding** | SWE-bench (Verified/Pro), LiveCodeBench | Resolve real GitHub issues; competitive programming | SWE-bench maturing + **scaffold/contamination-sensitive**; **LiveCodeBench** is time-windowed (contamination-resistant) |
| **Agentic / tool** | τ-bench / τ²-bench | Tool-using agents in realistic service domains, graded on end-state | Still hard; source of **`pass^k`** (reliability across k runs) |
| **Multimodal** | MMMU / MMMU-Pro | College-level image+text reasoning | Climbing; Pro is the frontier-separation version |
| **Long-context** | RULER, MRCR, Fiction.liveBench, NoLiMa | *Effective* vs advertised context | **Not saturated** — still clearly separates models (big drop-off past ~200K) |
| **Instruction-following** | IFEval | Verifiable format/constraint adherence ("respond in JSON", "≤400 words") | Mostly saturated; still isolates format adherence |
| **Human preference** | LMArena / Chatbot Arena | Crowd pairwise votes → Elo | Useful but **contested** (see below) |

The pattern: the classic knowledge/math MCQ benchmarks are now **floors** (a model failing
them is disqualified, but passing them doesn't separate the frontier); the discriminating
2026 set is HLE, FrontierMath, long-context, τ²-bench, and Pro-class coding.

## The caveats that matter most

These are the reason public benchmarks are a **starting signal, not a verdict** — and they
all reduce to one law.

- **Contamination** — test items leaked into training, so the score partly measures
  *memorized recall*, not reasoning. Documented across popular benchmarks; the reason for
  time-windowed (LiveCodeBench), held-out (FrontierMath), and rotated (AIME) designs.
- **Saturation** — once a benchmark is near 100%, it's lost discriminative power. Near-ceiling
  means the *benchmark* is finished, not that models are perfect.
- **Overfitting / teaching to the test** — training that lifts a benchmark can *hurt* general
  ability; agents have been caught reading a repo's `.git` history for the real fix on
  SWE-bench. Watch for benchmark gains that don't transfer.
- **Construct validity** — paraphrasing a question, renaming variables, or reordering MCQ
  options can swing scores, revealing the model exploited surface patterns, not the intended
  skill.
- **The Leaderboard Illusion** — even human-preference Elo (LMArena) is gameable: private
  testing of many variants with selective disclosure, data-access asymmetry between big labs
  and open models, and silent model deprecation were all documented in 2025. Use the
  **style-controlled / category** boards over the headline number, and remember Arena
  measures *preference, not correctness.* [(Leaderboard Illusion, 2025)](https://arxiv.org/html/2504.20879v1)

> **Goodhart's Law** unifies all of the above: *"when a measure becomes a target, it ceases
> to be a good measure."* Every caveat here is a measure that became a target. This is the
> deepest argument for the [private, task-specific, contamination-free eval](01-building-eval-sets.md)
> from your own data — and for weighting *reliability* (`pass^k`) over best-case capability
> ([lesson 05](05-evaluation-in-production.md)).

## How to actually use leaderboards

1. **Shortlist** with benchmarks relevant to your task ([Module 1](../part-01-model-landscape/00-how-to-choose-a-model.md)) —
   coding model → SWE-bench/LiveCodeBench; long-doc → RULER; agent → τ²-bench.
2. **Prefer contamination-resistant, still-discriminating** benchmarks over saturated ones.
3. **Decide** with your own private eval — the leaderboard never sees your data, your
   constraints, or your definition of "good."

## Safety / alignment / red-team evaluation

Safety eval **inverts** capability eval — it's worth understanding as its own mode:

| | Capability eval | Safety eval |
|---|---|---|
| Cares about | Average case | **Worst case** (the 1-in-1000 failure *is* the point) |
| The "user" is | Cooperative | **An adversary** |
| You want | High scores | **Low** scores (near-zero attack success) |
| Cadence | One-shot | **Ongoing** (new jailbreaks keep appearing) |

Plus a **dual objective**: refuse genuine harm *and* not over-refuse benign requests — so you
report *both* harmful-compliance and benign-refusal rates.

- **Harmfulness / refusal:** HarmBench; over-refusal diagnosed by XSTest / OR-Bench.
- **Jailbreak robustness:** AdvBench, JailbreakBench, StrongREJECT (a better grader).
- **Bias / fairness:** BBQ (Bias Benchmark for QA); HELM also scores bias/toxicity/fairness.
- **Automated red-teaming** — models generating attacks against models — scales coverage
  beyond hand-written tests.
- **Governance frameworks** (version-flagged, dated): Anthropic's Responsible Scaling
  Policy and OpenAI's Preparedness Framework define capability thresholds and required
  safeguards; national AI-safety/security institutes (UK, US) build evaluation tooling like
  **Inspect**.

This connects straight back to the agent-safety material ([Module 4, lesson 05](../part-04-agents-and-tool-use/05-safety-security-and-reliability.md)):
red-team/safety evals are how you *measure* the guardrails that lesson said to build.

---

## Next

→ [Evaluation in production](05-evaluation-in-production.md)
