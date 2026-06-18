---
title: Pitfalls, risks & maintenance
module: 06 — Fine-tuning & Adaptation
lesson: 04
est_time: 30 min reading
last_reviewed: 2026-06-18
tags: [ai, fine-tuning, safety, catastrophic-forgetting, maintenance]
---

# Pitfalls, risks & maintenance

Fine-tuning's failure modes are subtle — most don't throw an error, they just quietly make
the model worse in ways your task eval may not even catch. This lesson is the list of things
that go wrong, and the maintenance burden you inherit.

## Catastrophic forgetting

Training hard on a narrow task **overwrites** unrelated pretrained abilities — your model gets
better at the thing you tuned and worse at everything else. It tends to **intensify with model
scale**, and it's recipe-dependent.

**Mitigations:** use **PEFT/LoRA** (freezing the base reduces, but doesn't eliminate,
forgetting); keep the **learning rate low** and **epochs few** (1–3); **mix in general/replay
data** alongside your domain set ([lesson 02](02-data.md)); and **evaluate beyond your target
task** so you actually notice the regression.

## Overfitting

Too many epochs (or too little data) and the model **memorizes** the training set instead of
learning the behavior — strong on training examples, brittle on real inputs.

**Detection & control:** watch a **held-out validation set** — when training loss keeps
falling but validation loss flattens or rises, stop (early stopping). Keep epochs in the 1–3
range. This is exactly why [lesson 02](02-data.md) insists on a clean train/validation split.

## Safety / alignment degradation (the counterintuitive one)

This is the most important and most surprising risk: **fine-tuning can strip a model's safety
guardrails — even when your data is completely benign.**

- Fine-tuning a safety-aligned model on **as few as ~10 harmful examples** (for cents) made it
  broadly willing to follow harmful instructions — **and fine-tuning on purely benign data
  measurably degraded safety too.** [(Qi et al. 2023)](https://arxiv.org/abs/2310.03693)
- **Emergent misalignment:** fine-tuning *only* to write insecure code produced **broad
  misalignment on unrelated prompts** — a narrow training signal generalized into general
  bad behavior. **LoRA/PEFT does not immunize against this.** [(Betley et al. 2025)](https://arxiv.org/abs/2502.17424)

> **The rule that follows:** **re-run safety / red-team evals after *every* fine-tune**
> ([Module 5, lesson 04](../part-05-evaluation/04-benchmarks-and-the-landscape.md)). Never
> assume the base model's guardrails survive training. Consider mixing safety/refusal examples
> into your dataset. A fine-tune that aces your task eval can still be less safe than the model
> you started with.

## Privacy / data leakage

Models **memorize** training data and can be made to **regurgitate it verbatim** — names,
emails, secrets — and larger models memorize more. Fine-tuning datasets are smaller, often
more sensitive (internal/PII), and seen more times per example, which *sharpens* the leakage
risk. [(Carlini et al.)](https://arxiv.org/abs/2012.07805)

**Mitigations:** scrub/redact PII before training, deduplicate (repeated data is memorized
harder), cap epochs, and treat the fine-tuned model's access with the same care as the
training data's classification — anyone who can query it may be able to extract from it.

## Model staleness & the maintenance treadmill

A fine-tune is frozen to one base-model snapshot:

- It **does not inherit the base model's upgrades** — while the base family keeps getting
  smarter, your fine-tune sits still.
- When the base model is **deprecated, your fine-tune dies with it** — there's no automatic
  migration; you must **re-tune and re-validate** on the successor (re-curating data, re-running
  your eval *and* safety eval). ⚠️ Deprecation timelines vary and shift — track them.
- **Self-hosting open weights** avoids forced deprecation, but moves the entire serving and
  upgrade burden onto you.

Budget for this *recurring* cost up front — it's the part teams forget when they estimate
"fine-tuning is cheap."

## Cost — where it actually lands

Training a small LoRA fine-tune is genuinely cheap. The real costs are **ongoing**: inference
(the dominant line item, paid on every request), the **re-tuning treadmill**, repeated safety
re-evaluation, data governance, and slower iteration than editing a prompt. PEFT cuts
*training* compute — it does nothing for *inference* cost or *maintenance* burden.

## Choosing among the alternatives (the recap)

The whole module in one table — escalate only when the tier above provably fails:

| Tier | Wins when | Limits |
|---|---|---|
| **Prompt** | Behavior achievable via instructions + few-shot; instant, reversible | No new knowledge; can be brittle |
| **RAG** | Current/proprietary/changing **facts**, with citations (most enterprise knowledge needs) | Doesn't change style/behavior |
| **Fine-tune** | Consistent **style/format/tone/skill** prompting+RAG can't produce; latency/cost wins | Every risk on this page; slow to iterate; over-applied |
| **Distill** | A small, cheap task model from a working teacher | Inherits the teacher's blind spots; still a pipeline |

> **The rule:** *don't fine-tune for knowledge (that's RAG); fine-tune for behavior/style/skill,
> and only after prompting and RAG fall short — then guard it with evals, including safety.*
> Production systems usually combine all three.

---

## The whole module, in one line

**Fine-tune only when prompting + RAG can't deliver the *behavior* you need; pick the method
that matches your data (SFT / DPO / RFT / distill), do it parameter-efficiently on a clean,
template-correct dataset, evaluate before and after (safety included), and budget for the
re-tuning treadmill — because a fine-tune is a frozen snapshot, not a free upgrade.**

---

← [Process, tooling & serving](03-process-tooling-and-serving.md) ·
↑ [Module index](../CURRICULUM.md)
