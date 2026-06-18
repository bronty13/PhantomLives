---
title: Building eval sets
module: 05 — Evaluation
lesson: 01
est_time: 35 min reading
last_reviewed: 2026-06-18
tags: [ai, evaluation, datasets, golden-set, contamination]
---

# Building eval sets

The eval set — the "golden dataset" — is where the discipline lives or dies. It's a
**living, human-driven artifact**, not a static target you write once. This lesson is how
to build, label, split, and grow one.

## What a good eval set is

Each item pairs an **input** with an **expected output or pass/fail criterion**. Make the
success criteria **SMART** — Specific, Measurable, Achievable, Relevant. Even fuzzy goals
get quantified:

| Weak | Strong |
|---|---|
| "Outputs should be safe" | "< 0.1% of 10,000 outputs flagged for toxicity" |
| "Classify sentiment well" | "F1 ≥ 0.85 on a held-out set of 10,000 diverse posts" |

A useful test for a well-formed item (Anthropic): *two domain experts, given the task,
would independently reach the same pass/fail verdict* — and everything the grader checks is
clear from the task. Most real systems need **multidimensional** criteria (correctness *and*
tone *and* latency *and* cost), not one number.

> **Calibration check:** if you're passing ~100% of your evals, the set is too easy — you're
> not challenging the system. ~70% is often where an eval is actually informative.

## Coverage — including the cases that *shouldn't* trigger

Cover **typical, edge, and adversarial** inputs — input variety (non-English, JSON/CSV),
contextual complexity (typos, long histories, ambiguous tool output), and adversarial
conflicts (jailbreaks, instructions that fight the system prompt).

The easily-missed half: **negative examples.** Test both where a behavior *should* occur
and where it *shouldn't.* A PII-redaction eval needs no-PII queries too — otherwise a model
that redacts *everything* scores perfectly. *"One-sided evals create one-sided
optimization."* And watch **class balance**: under imbalance, measure **precision and recall
separately**, never raw accuracy ([lesson 02](02-grading-methods.md)).
[(Anthropic — Demystifying evals)](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents) ·
[(OpenAI — eval best practices)](https://developers.openai.com/api/docs/guides/evaluation-best-practices)

## Where the data comes from

Mix your sources:

- **Production logs/traces** — the richest. Convert bug-tracker and support-queue failures
  straight into test cases.
- **Expert-hand-written** — start by writing ~20 input/output pairs yourself.
- **Synthetic — done well.** You don't have to wait for production data, but don't naïvely
  ask "give me test cases." Look at real data first, identify the *dimensions* that matter
  (personas × features × scenarios), and generate *along those dimensions*. Two caveats:
  don't synthesize tests for bugs you can just fix now, and **filter synthetic data through
  your own assertions/judges** before trusting it.
  ⚠️ Synthetic data from the *same model family you're evaluating* biases toward that
  model's style — supplement real traces with it, don't replace them.

## How many examples — volume over polish

> **"More questions with slightly lower-signal automated grading beats fewer questions with
> high-quality hand grading."** — Anthropic

Two regimes, don't confuse them:

- **Bootstrapping:** 20–50 tasks (or ≥100 traces for error analysis) gets you started. Stop
  adding when ~20 fresh traces surface no new failure category (saturation).
- **Shipping-grade:** hundreds-to-thousands per slice — because *distinguishing* two systems
  that differ by a few points needs enough examples that the confidence interval is narrower
  than the difference you care about ([lesson 05](05-evaluation-in-production.md)).

## Labeling / ground truth

- **Who labels:** a single domain expert as "benevolent dictator" beats a committee — it
  avoids endless annotator reconciliation. Bring in inter-annotator agreement
  ([lesson 02](02-grading-methods.md)) only when multiple raters are unavoidable.
- **How:** open-code → cluster → **binary good/bad before any granular scoring.** Binary
  forces clearer, more consistent labels.
- **Store** `input` + `expected_output` (the golden); generate `actual_output` at eval time
  by running the system. Pair each task with a **reference solution** that passes all
  graders — a 0% pass rate usually means a *broken task*, not an incapable model.

## Train / dev / test split — don't grade on what you tuned

If you tune your prompt against the same examples you report on, you **overfit to the eval
set** and your numbers lie. Keep a **held-out test split** you touch rarely (ideally only at
release gates). Vocabulary varies across tools (train/dev/test, dev/holdout, a curated
regression suite) — the universal rule is *don't report on data you optimized against.*

## Data contamination — the case for *private, fresh* sets

**Contamination** is test data leaking into a model's training set, so it scores by
memorization instead of reasoning — inflating results. It comes in three grades: exact
(verbatim), semantic (paraphrased), and domain (same distribution). Studies find
contamination across popular public benchmarks, and *detect-then-filter provably fails*
under moderate contamination. [(survey)](https://arxiv.org/html/2601.19334v1)

Two consequences:

1. **Public benchmarks are contamination-suspect by construction** (they've been on the
   internet for years — [lesson 04](04-benchmarks-and-the-landscape.md)).
2. **A private eval built from your own production traces is contamination-free by
   construction** — a major reason to trust it over leaderboards.

> ⚠️ **Never publish your private eval set verbatim.** The moment it's on the internet it
> becomes future training data and loses its value. Keep it private; use fresh, post-cutoff
> data where you can.

## Maintaining & growing the set

An eval set is never done:

- **Add production failures continuously** — every real-world miss becomes a permanent case.
- **Retire saturated cases into a regression suite** — once a case reliably passes, it
  guards against regressions rather than driving improvement.
- **Version it.** A score is only comparable over time if you know which dataset version
  produced it — pin and version eval sets like code.

---

## Next

→ [Grading methods](02-grading-methods.md)
