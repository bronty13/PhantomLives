---
title: LLM-as-a-judge
module: 05 — Evaluation
lesson: 03
est_time: 35 min reading
last_reviewed: 2026-06-18
tags: [ai, evaluation, llm-as-judge, bias]
---

# LLM-as-a-judge

For open-ended output that code can't grade — tone, faithfulness, helpfulness, reasoning
quality — the scalable option is to use *another LLM as the grader*. It's powerful and
genuinely useful, and it's full of traps. This lesson is how to do it well. (It's the third
rung of the [grading hierarchy](02-grading-methods.md), and it appeared in the prompt, RAG,
and agent eval lessons — here's the full treatment.)

## The foundation: it works, *if validated*

The result that legitimized the technique: a strong LLM judge reaches **>80% agreement with
human preferences — about the level humans agree with each other.** That makes it a
scalable, explainable *approximation* of human judgment — not a replacement for it.
[(Zheng et al., MT-Bench / Chatbot Arena, 2023)](https://arxiv.org/abs/2306.05685)

The catch, and the through-line of this lesson: an LLM judge is only trustworthy **once
you've validated it against human labels.** The highest-leverage work isn't a clever judge
prompt — it's the error analysis and human calibration behind it. (A judge is partly *"a
hack to trick you into looking carefully at your data."*)

## The three grading modes

| Mode | What it does | Use when | Watch |
|---|---|---|---|
| **Pointwise / absolute** | Score one output (pass/fail or 1–5) | Production monitoring, CI gating (scales O(n)) | LLMs are **bad at fine-grained absolute scores** — keep cardinality low |
| **Pairwise** | Pick the better of A vs. B | Comparing two systems/prompts | More **stable** than absolute scoring, but most exposed to position bias |
| **Reference-based** | Compare output to a supplied gold answer | You have a gold answer *and* the task isn't code-checkable | For verifiable facts, plain string match can beat it (judge "over-reasons") |

Default: **pointwise-binary** for scalable monitoring; **pairwise** to compare; reference-
based only with a gold answer for a non-checkable task.

## Writing a good judge prompt

- **Low-cardinality verdicts — binary beats 1–10.** Numeric scales aren't actionable
  ("what do I do with a 3?"), invite middle-dodging, and need bigger samples to detect a
  real difference. Replace "rate accuracy 1–5" with atomic pass/fail sub-checks ("are all 5
  required facts present?"). If you must use a scale, a small *integer* (1–4) with each point
  described — never a continuous range.
- **Reason-then-score.** Ask the judge to reason *before* emitting the verdict, then parse
  only the verdict — this improves judgment on hard cases. (e.g. `<thinking>…</thinking>`
  then `<result>correct</result>`.)
- **Decompose into specific judges**, one per failure mode, rather than one vague "is this
  good?" — but only *after* error analysis shows where errors cluster (resist metric sprawl).
- **Few-shot the judge** with diverse, expert-authored pass/fail/edge examples + short
  critiques.
- **Give it an escape hatch** — an explicit "Unknown / can't tell" so it abstains instead of
  guessing, surfacing ambiguous cases for human review. Parse verdicts deterministically
  (tags / structured output), and give the judge **the same context a human grader would
  have.**

## The biases — and how to fight them

LLM judges have systematic, measurable biases. Know all four:

| Bias | The judge tends to… | Mitigation |
|---|---|---|
| **Position** | Favor the first (or second) answer in a pairwise comparison | Run **both orderings**, only count a win if it holds both ways |
| **Verbosity / length** | Prefer the longer answer regardless of quality | Control for length; instruct it to ignore length; binary verdicts are harder to game |
| **Self-preference** | Favor outputs from its **own model family** | **Use a different model to judge than the one that generated the output** |
| **Sycophancy** | Be swayed by confident phrasing / claimed authority | Strip persuasive framing; ground the verdict in the rubric + reference |

(These mitigations also appeared in [Module 2, lesson 04](../part-02-prompt-engineering/04-reliability-security-and-evaluation.md) —
here's why each exists.)

**Cross-cutting moves:**
- **LLM jury / panel (PoLL).** Several *diverse, smaller* judges voting often beats one big
  judge — less intra-model bias and much cheaper. A good lever for both quality and cost.
- **Calibrate against human labels, and report the agreement number.** Measure judge↔human
  agreement (Cohen's κ, or precision/recall under imbalance) on a labeled gold set *before*
  you trust the judge as a release signal. **Never report an LLM-judge metric without a
  human-agreement number behind it.**

## When a judge is the right tool

Walk the [hierarchy](02-grading-methods.md):

1. **Code** if the property is verifiable (exact/regex/schema/tool-success).
2. **LLM judge** only for genuinely non-checkable qualities — *and* only after validating it.
3. **Human** for ground truth and high-stakes/ambiguous cases — the calibration target.

A judge that grades something a regex could check is wasted cost and added noise.

## Cost, latency, nondeterminism, versioning

- **Don't put an expensive judge in the synchronous request path** — run it *async on
  sampled* traffic (a compact judge model is fine for inline guardrails).
- **Nondeterminism** — hosted APIs aren't bit-deterministic even at temperature 0; keep judge
  temperature low and rerun borderline cases.
- **Version the judge.** A silently-updated judge model moves your metrics for reasons that
  have nothing to do with your product. Pin the judge model version and the judge prompt (in
  git), and record which judge version produced which result.

## The takeaway

An LLM judge is the right tool for nuanced, non-checkable quality at scale — but it is an
*instrument you must calibrate*, not an oracle. Validate it against humans, fight its
biases, use the cheapest verdict that works (usually binary), and version it like code.

---

## Next

→ [Benchmarks & the landscape](04-benchmarks-and-the-landscape.md)
