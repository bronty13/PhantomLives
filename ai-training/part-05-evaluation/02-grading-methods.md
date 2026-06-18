---
title: Grading methods
module: 05 — Evaluation
lesson: 02
est_time: 30 min reading
last_reviewed: 2026-06-18
tags: [ai, evaluation, grading, metrics, classification]
---

# Grading methods

Once you have an eval set ([lesson 01](01-building-eval-sets.md)), you need to **score** the
outputs. There's a reliability hierarchy — and the rule is to **choose the fastest, most
reliable, most scalable method that actually works** for each check, escalating only when
you must.

```
code-based  >  LLM-as-judge  >  human
(reliability, speed, scale)   (nuance, cost)
```

Code-based is cheapest and most trustworthy but can't judge nuance; human is the gold
standard but slow; LLM-as-judge sits between (and gets its own [lesson 03](03-llm-as-judge.md)).
Most real systems **layer** them: deterministic checks first, a judge for what code can't
verify.

## 1. Code-based / deterministic — prefer whenever checkable

If a property can be verified by code, verify it by code: fast, free, perfectly
reproducible, zero rater noise.

- **Exact match** — normalize then compare (`output.strip().lower() == expected`).
- **Substring / keyword** — required phrase present?
- **Regex assertions** — e.g. "an internal UUID never appears in output." Needn't be fancy.
- **Schema / structural validation** — does it parse? right fields, types, enums?
- **Tool-call correctness** — right tool, right arguments, right order
  ([Module 4, lesson 06](../part-04-agents-and-tool-use/06-evaluating-and-operating-agents.md)).
- **Execution-based** — run generated code against unit tests (the `pass@k` family —
  [lesson 05](05-evaluation-in-production.md)).

> **Guardrails vs. evaluators.** Deterministic checks that run *synchronously in the request
> path* (block PII, profanity, malformed JSON) are **guardrails** — they must be
> millisecond-fast with near-zero false positives. **Evaluators** run *async* and may use
> fuzzier methods. Same techniques, different latency budget and stakes.

**Limit:** code can't judge tone, faithfulness, or completeness of free text. Don't escalate
prematurely, though — *you may not even need an LLM judge for many checks.*

## 2. Statistical / NLP reference metrics — handle with care

Reference-based metrics compare output to a gold answer by surface overlap. Know them, but
know their ceiling:

| Metric | Measures | Weakness |
|---|---|---|
| **BLEU** | n-gram precision (+ brevity penalty) | Surface overlap; blind to meaning |
| **ROUGE-1/2/L** | n-gram recall / longest common subsequence | Rewards lexical overlap, not correctness |
| **METEOR** | precision+recall w/ stemming & synonyms | Still reference-dependent |
| **Embedding cosine** | sentence-embedding similarity | High score ≠ correct |
| **BERTScore** | contextual-embedding token matching | Model/language dependent |

**The core problem: they correlate poorly with human judgment on open-ended output** — they
reward fluent-but-wrong text and penalize correct paraphrases, and they need reference
answers you often don't have. *Tangled up in BLEU* documents how brittle and outlier-
sensitive these correlations are. [(ACL 2020)](https://arxiv.org/abs/2006.06264)

**Practitioner verdict:** these are *"notably unhelpful for most LLM applications, though
they retain utility in retrieval optimization for RAG"* (where you *do* have references and
care about overlap — [Module 3](../part-03-rag/05-evaluation-security-and-production.md)).
Don't make BLEU/ROUGE your product's headline metric.

## 3. Classification metrics — for anything that reduces to labels

The moment your eval produces discrete labels — sentiment, pass/fail, PII present/absent,
*or the verdict of an LLM judge* (a judge **is** a classifier) — use classification metrics,
not raw "accuracy."

- **Accuracy** is misleading under imbalance — a 1%-positive class scores 99% by always
  guessing "negative."
- **Precision** = TP/(TP+FP) — prioritize when **false positives** are costly (a guardrail
  blocking legitimate output).
- **Recall** = TP/(TP+FN) — prioritize when **false negatives** are costly (missing a PII
  leak or a toxic output).
- **Precision–recall tradeoff** — raising the decision threshold trades recall for precision.
- **F1** = harmonic mean of the two — the standard single number for imbalanced classes.
- **Macro vs. micro** — micro pooling is dominated by the majority class; **macro** weights
  classes equally and surfaces minority-class failures. Use macro when the rare class
  matters.

To validate a judge or guardrail, report its **true-positive and true-negative rates against
human labels**, not a generic accuracy figure.

## 4. Human evaluation — gold standard, used sparingly

Humans are the most flexible and highest-quality graders, and **slow and expensive** — so
use them to *calibrate* the automated methods, not as the routine loop.

- **Binary (pass/fail)** beats fine-grained scales — it forces clearer, more consistent
  labels.
- **Rubric-based** — score each dimension against an explicit rubric, in isolation.
- **Pairwise (A vs. B)** is often more reliable than absolute scoring.
- **Inter-annotator agreement** when you have multiple raters: **Cohen's κ** (two raters),
  **Fleiss' κ** (3+), **Krippendorff's α** (any number/data type). Rough κ bands: 0.41–0.60
  moderate, 0.61–0.80 substantial, 0.81+ near-perfect. ⚠️ These thresholds are conventions,
  and recent work argues they're too rigid for genuinely subjective tasks — treat them as a
  guide, not a gate.

**Human labels are the validation harness for everything automated** — your code checks and
especially your LLM judge ([lesson 03](03-llm-as-judge.md)) should be measured against a
human-labeled sample before you trust them at scale.

## Composing methods

A mature eval is **layered**, not monolithic: deterministic guardrails catch the cheap
hard-failures synchronously; code-based checks grade everything verifiable; an LLM judge
handles the nuanced remainder; and a human-labeled sample calibrates the judge. Reach down
the hierarchy for reliability, up it only for nuance.

---

## Next

→ [LLM-as-a-judge](03-llm-as-judge.md)
