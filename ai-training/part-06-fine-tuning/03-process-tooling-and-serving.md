---
title: Process, tooling & serving
module: 06 — Fine-tuning & Adaptation
lesson: 03
est_time: 30 min reading
last_reviewed: 2026-06-18
tags: [ai, fine-tuning, tooling, qlora, serving, lora]
---

# Process, tooling & serving

How a fine-tune actually gets built and shipped: the workflow, the platforms and frameworks,
the hardware, the hyperparameters in practice, and how to serve the result.

> ⚠️ **Dated snapshot — June 2026.** The tooling/provider landscape moves fast (OpenAI is
> winding down hosted fine-tuning; offerings, prices, and supported models churn). The
> *workflow* and *concepts* are stable; verify the *who/what* before committing.

## The workflow (prompt/RAG first)

Fine-tuning is the *last* step of a loop, not the first:

```
1. Baseline with prompting + RAG     ([Module 2](../part-02-prompt-engineering/00-prompting-fundamentals.md), [Module 3](../part-03-rag/00-rag-fundamentals.md))
2. Build an eval set + measure        ([Module 5](../part-05-evaluation/00-the-eval-mindset.md))  ← BEFORE you train
3. Only if behavior/format/tool failures remain → curate data ([lesson 02](02-data.md))
4. Train (SFT/LoRA, then DPO if needed)
5. Evaluate against the held-out set + RE-RUN SAFETY EVALS    ([lesson 04](04-pitfalls-risks-and-maintenance.md))
6. Iterate, or ship and monitor
```

Step 2 is the one teams skip — and then they can't tell whether the fine-tune helped. The
division of labor stays constant: **RAG for facts, fine-tuning for behavior, prompts for
control.**

## Hosted vs. DIY

**Hosted fine-tuning** (you upload data, they train + serve):

| Platform | Notes (dated) |
|---|---|
| **OpenAI** | SFT / DPO / RFT — ⚠️ **being wound down**; don't build new work on it |
| **Google Vertex AI** | LoRA-based SFT + DPO for Gemini; billed per training token |
| **Amazon Bedrock** | SFT, continued pretraining, distillation; Claude (Haiku), Llama, Nova, etc.; strong data isolation |
| **Together / Fireworks / Predibase** | Open-weight LoRA SFT/DPO (and RFT on Predibase); priced per training token |

**DIY open-source** (you run the training on your own/rented GPUs — the most durable route,
no forced deprecation):

| Framework | Best at |
|---|---|
| **Hugging Face TRL + PEFT** | The reference — SFT, DPO, GRPO, PPO; PEFT supplies LoRA/QLoRA |
| **Axolotl** | Config-driven (YAML), batteries-included |
| **Unsloth** | Speed + memory — ~2× faster, much less VRAM |
| **LLaMA-Factory** | Widest model coverage + a web UI; low friction |
| **torchtune** | PyTorch-native, minimal abstractions — for modifying the loop |

These increasingly compose (e.g. Unsloth kernels under TRL trainers).

## Hardware — QLoRA changed the game

QLoRA put large-model fine-tuning on a single GPU. Rough VRAM minimums (add headroom for
batch size / sequence length):

| Model | QLoRA (4-bit) | LoRA (16-bit) |
|---|---|---|
| 7B | ~5 GB | ~19 GB |
| 8B | ~6 GB | ~22 GB |
| 70B | ~41 GB | ~164 GB |

So a 7B QLoRA fine-tune runs on a mid-range consumer card; a 70B QLoRA on a single 48 GB
prosumer card. (The same memory math as running models locally —
[Module 1, lesson 02](../part-01-model-landscape/02-open-weight-local-ecosystem.md).)

## Hyperparameters in practice

Sensible starting points (then tune against your eval — [lesson 01](01-methods.md) explains
what each does):

- **Epochs:** 1–3 (more than 3 → diminishing returns + overfitting risk).
- **Learning rate:** ~`2e-4` for LoRA/QLoRA; much lower (~`5e-6`) for RL methods (DPO/GRPO).
- **LoRA rank `r`:** start 16 or 32; **`alpha` = `r` or `2r`**.
- **Batch size:** scale with dataset size (effective batch ~4–16 is a common target).

Change one thing at a time and re-measure — same discipline as prompt iteration.

## Evaluation — non-negotiable, both directions

Use [Module 5](../part-05-evaluation/00-the-eval-mindset.md): measure the **baseline before**
fine-tuning and the **fine-tune after**, on the same held-out set, with confidence intervals
(a 2-point move is usually noise). And critically — **re-run safety/red-team evals**, because
fine-tuning can degrade safety even on benign data ([lesson 04](04-pitfalls-risks-and-maintenance.md)).

## Serving — merged weights vs. swappable adapters

- **Merged weights** — fold the LoRA adapter into the base and serve it as one model. Simplest
  when you have a *single* fine-tune. (Hosted providers typically serve fine-tunes at ~base
  inference price.)
- **Multi-LoRA** — keep one base model in memory and attach lightweight LoRA adapters per
  request. This is the big operational advantage of LoRA: serve many fine-tunes from one base.
  - **vLLM** supports multi-LoRA with runtime load/unload (request picks the adapter).
  - **LoRAX** can serve hundreds-to-thousands of adapters on one GPU with dynamic loading and
    batching across different adapters.
- **Heuristic:** one fine-tune → merge and serve; many fine-tunes over one base → multi-LoRA.

---

## Next

→ [Pitfalls, risks & maintenance](04-pitfalls-risks-and-maintenance.md)
