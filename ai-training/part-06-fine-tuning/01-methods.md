---
title: Methods
module: 06 — Fine-tuning & Adaptation
lesson: 01
est_time: 35 min reading
last_reviewed: 2026-06-18
tags: [ai, fine-tuning, lora, qlora, dpo, distillation]
---

# Methods

There are several ways to move a model's weights, and they answer different questions:
*"do what I demonstrate"* (SFT), *"prefer this over that"* (DPO/RLHF), *"maximize this
verifiable score"* (RFT), *"imitate this bigger model"* (distillation), or *"absorb this
domain"* (continued pretraining). And cutting across all of them: *full* vs.
*parameter-efficient* training.

## Full vs. parameter-efficient (PEFT): LoRA & QLoRA

**Full fine-tuning** updates every weight. For modern LLMs that's expensive in compute,
memory, and storage (each task = a full model copy), and rarely necessary.

**PEFT** trains a tiny number of extra parameters and freezes the rest — comparable quality
at a fraction of the cost, feasible on consumer hardware.

- **LoRA (Low-Rank Adaptation)** — freeze the pretrained weights, inject small trainable
  low-rank matrices into each layer. Cuts trainable parameters by ~10,000× and GPU memory by
  ~3× vs. full fine-tuning, with **no added inference latency** (the adapter can be merged
  back). [(Hu et al. 2021)](https://arxiv.org/abs/2106.09685)
- **QLoRA (Quantized LoRA)** — train LoRA adapters on top of a **frozen 4-bit** base
  (NF4 quantization + paged optimizers). Fine-tune a 65B model on a *single 48 GB GPU* at
  near-16-bit quality. This is what democratized large-model fine-tuning.
  [(Dettmers et al. 2023)](https://arxiv.org/abs/2305.14314)

**Why LoRA/QLoRA dominate:** memory and cost, plus **swappable adapters** — one frozen base
model can host many small task adapters loaded per request, instead of N full copies (see
serving in [lesson 03](03-process-tooling-and-serving.md)).

## Supervised fine-tuning (SFT) — the workhorse

Train on **(input → ideal output)** pairs: you show the model correct examples and it learns
to imitate them. This is the right method for the bulk of fine-tuning goals — format, tone,
classification, extraction, domain-specific generation. Most managed services and the gains
in [lesson 00](00-fundamentals-and-when-to-fine-tune.md) are SFT (usually SFT + LoRA).

## Preference / alignment tuning

When there's no single "correct" output, you teach the model *which of two responses is
better*:

- **RLHF** — the original: train a reward model from human preference labels, then optimize
  the policy with RL (PPO). Powerful but heavy and unstable (separate reward model + online
  sampling, prone to reward hacking).
- **DPO (Direct Preference Optimization)** — reparameterizes the problem so preference tuning
  becomes a **simple classification loss** — **no separate reward model, no sampling during
  training.** Stable, lightweight, and matches or beats PPO-RLHF on common tasks. The modern
  default for preference tuning. [(Rafailov et al. 2023)](https://arxiv.org/abs/2305.18290)
- **Successors** — **KTO** learns from *unpaired* binary good/bad labels (cheaper data);
  **ORPO** fuses SFT + preference into one pass (no reference model); **IPO** curbs DPO's
  overfitting. Pick by what data you have and what you're fixing.

Data shape: DPO and friends need `{prompt, chosen, rejected}` triples ([lesson 02](02-data.md)).

## Reinforcement fine-tuning / RL with verifiable rewards (RFT / RLVR)

For **reasoning and verifiable** tasks. Instead of a fixed gold answer, you supply a
**programmable grader**; the trainer samples several candidate answers, scores them, and
nudges the model toward high-scoring outputs. The reward is **rule/grader-determined
("verifiable"), not a learned reward model** — that's the RLVR distinction.

Fit criteria: the task is **clearly verifiable**, **gradable without a human**, and **the
base model can already solve it *occasionally*** — RFT sharpens a latent ability; it can't
conjure one from nothing (if the base scores 0% or 100%, RFT won't help).
[(OpenAI — RFT)](https://developers.openai.com/api/docs/guides/reinforcement-fine-tuning)
⚠️ As of mid-2026 OpenAI's RFT runs on o-series reasoning models only — a moving target.
Conceptually, this is the same RLVR idea behind modern reasoning-model training
([Module 1](../part-01-model-landscape/01-frontier-proprietary-models.md)).

## Distillation (teacher → student)

Train a small **student** model on a large **teacher's** outputs (sometimes its rationales),
capturing most of the capability at a fraction of the inference cost. This is the practical
engine behind "a small fine-tuned model beats a big prompted one," and behind many of the
local reasoning-distill models in [Module 1's catalog](../part-01-model-landscape/03-top-100-local-models.md).
Usually it's SFT on teacher-generated data. ⚠️ Mind licensing — major providers' terms
forbid using their outputs to train competing models ([lesson 02](02-data.md)).

## Continued / domain-adaptive pretraining

The **knowledge-bearing** form of weight training: keep running the pretraining objective on
a large *unlabeled* domain corpus (legal, medical, a new language) so the model absorbs the
domain before any task SFT. Use it only for a genuine new **domain or language** with a large
corpus — for narrow knowledge needs, RAG is cheaper and stays fresh. Its main hazard is
**catastrophic forgetting** of general ability ([lesson 04](04-pitfalls-risks-and-maintenance.md)).

## Hyperparameters (high-level)

You don't need to be an optimization expert, but know the dials
([practical values in lesson 03](03-process-tooling-and-serving.md)):

- **Epochs** — passes over the data. Small datasets need a few; too many → overfitting.
  Typical LoRA range is **1–3**.
- **Learning rate** — bigger = faster but less stable. (LoRA commonly ~`2e-4`; RL methods
  much lower, ~`5e-6`.)
- **LoRA rank `r` + `alpha`** — `r` is the adapter's capacity (higher = more expressive,
  more cost); `alpha` scales its contribution; common heuristic is `alpha ≈ r` or `2r`.

## Picking a method

| You want to… | Method |
|---|---|
| Make a demonstrated behavior reliable (format, tone, narrow task) | **SFT** (+ LoRA/QLoRA) |
| Steer toward "better" when there's no single right answer | **DPO** (or KTO/ORPO) |
| Maximize a verifiable score on reasoning/code | **RFT / RLVR** |
| Shrink a working big model into a cheap one | **Distillation** (→ SFT the student) |
| Teach a whole new domain/language | **Continued pretraining** |

And almost always do it **parameter-efficiently** (LoRA/QLoRA) unless you have a specific
reason for full fine-tuning.

---

## Next

→ [Data](02-data.md) — where fine-tuning actually succeeds or fails.
