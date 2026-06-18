---
title: Data
module: 06 — Fine-tuning & Adaptation
lesson: 02
est_time: 30 min reading
last_reviewed: 2026-06-18
tags: [ai, fine-tuning, data, chat-template, synthetic-data]
---

# Data

Fine-tuning *is* a data problem. The method matters less than the examples you feed it —
this is where fine-tunes succeed or quietly fail. The dominant lesson across every source:
**quality beats quantity, and format correctness is non-negotiable.**

## Quality beats quantity

The famous result — **LIMA**: a 65B model fine-tuned on **just 1,000 carefully curated
examples** (no RLHF) reached near-frontier quality, because *"almost all knowledge is learned
during pretraining, and only limited instruction data is needed to teach the model to produce
high-quality output."* [(LIMA, 2023)](https://arxiv.org/abs/2305.11206)

The practical corollary: **if 50 high-quality examples don't move your eval, more data won't
fix it — fix the task, the prompt, or the format first.** Bad examples actively teach bad
behavior.

## How much data?

Method-dependent — treat these as starting points, not laws:

| Goal | Rough amount |
|---|---|
| Demonstrate output *shape* | 10–50 examples |
| Real gains on a narrow task (SFT/LoRA) | hundreds to low-thousands |
| Broad instruction/style alignment | ~1,000 *curated* (LIMA) |
| Inject a new **domain/knowledge** (continued pretraining) | far more — large corpora *(and reconsider: should this be RAG?)* |

## Format — and matching the chat template (the #1 silent failure)

Two shapes: plain `prompt → completion` strings, or **conversational `messages`** arrays
(`{role, content}` with `system`/`user`/`assistant`). Hosted services want JSONL (one example
per line); SFT typically trains only on the **assistant** turns (the user turns are masked).

> ⚠️ **The most common silent fine-tuning bug: a chat-template mismatch.** Every instruct
> model has specific control tokens (`[INST]…[/INST]`, `<|user|>…<|assistant|>`, …) and a
> specific `EOS` token. If your training data uses different control/EOS tokens than the
> model expects, performance degrades badly — with no error. Use the model's own template
> (`tokenizer.apply_chat_template`), make sure your data's EOS matches the template's, and
> don't double up special tokens. [(HF — chat templating)](https://huggingface.co/docs/transformers/main/en/chat_templating)

## Curation & cleaning

- **Match production.** Examples should look like the real inputs and outputs you'll see at
  inference — same diversity in train and holdout.
- **Decontaminate against your eval set.** Any overlap between training and eval data inflates
  your scores and hides regressions — check for n-gram/substring overlap and remove it
  ([Module 5, lesson 01](../part-05-evaluation/01-building-eval-sets.md)).
- **Dedup and prune** — drop duplicates, malformed examples, and anything inconsistent in
  label or format. Consistency is itself a signal the model learns.

## Diversity & coverage

- Cover the **range** of inputs you expect (and the edge cases) — a one-sided dataset
  produces one-sided behavior.
- **Mix in some general data.** Blending a little general instruction data with your
  domain-specific set helps prevent the model from over-specializing and **forgetting**
  unrelated abilities ([lesson 04](04-pitfalls-risks-and-maintenance.md)).

## Synthetic data & distillation

You don't always need production data — you can generate it:

- **Self-Instruct / bootstrapping** — use a strong model to generate instruction/response
  examples, then filter near-duplicates and low-quality ones.
- **Distillation** — generate the dataset from a stronger *teacher* model, then SFT the
  student on it ([lesson 01](01-methods.md)).
- **Do it carefully:** seed with a handful of real, hand-checked examples; **validate
  synthetic data through your own checks/judges** before training on it
  ([Module 5, lesson 03](../part-05-evaluation/03-llm-as-judge.md)); and beware that synthetic
  data from the *same model family you're tuning* bakes in that model's style/biases.
- ⚠️ **Licensing:** major providers' terms **prohibit using their model outputs to train
  competing models.** The clean path is synthetic data from **open-weight models you're
  licensed to use, or your own models.**

## Preference data (for DPO and friends)

Preference methods need **`{prompt, chosen, rejected}`** triples — a prompt with a better and
a worse response. Both responses must be formatted with the model's chat template. (KTO is the
exception — it accepts *unpaired* good/bad labels, which are cheaper to collect.)

## Train / validation split

Hold out a **representative** validation set *before* you train — and **decontaminate** it
against the training data so no example leaks across. Without a clean holdout you can't detect
overfitting ([lesson 04](04-pitfalls-risks-and-maintenance.md)) or know whether the fine-tune
actually helped. This is the same eval discipline from
[Module 5](../part-05-evaluation/01-building-eval-sets.md) — fine-tuning needs it *before* you
start, not after.

## The one-paragraph version

Curate a small, clean, diverse dataset that *looks like production*; format it in the model's
exact chat template; decontaminate it against a held-out eval set; generate synthetic data
only with real seeds, validation, and license-clean sources. Get the data right and the method
is almost an afterthought; get it wrong and no method saves you.

---

## Next

→ [Process, tooling & serving](03-process-tooling-and-serving.md)
