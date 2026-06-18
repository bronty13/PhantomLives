---
title: Generation & prompt assembly
module: 03 — Retrieval-Augmented Generation
lesson: 04
est_time: 30 min reading
last_reviewed: 2026-06-18
tags: [ai, rag, generation, citations, grounding, lost-in-the-middle]
---

# Generation & prompt assembly

You've retrieved good chunks. Now turn them into a grounded, cited answer. This is just
prompt engineering with retrieved context — so the core moves (grounding instructions,
citations, "I don't know," structured output) come from
[Module 2, lesson 04](../part-02-prompt-engineering/04-reliability-security-and-evaluation.md).
This lesson covers the **RAG-specific** parts: where to put chunks, how many, and how to
make the model cite them.

## 1. Grounding — "answer only from the context"

The defining RAG instruction forbids the model from falling back on its training
knowledge and confines it to the retrieved chunks:

```text
Answer the question using ONLY the information in the documents above.
Do not use prior knowledge. If the documents don't contain the answer, say so —
do not fill gaps from memory. Cite the source index for each claim, e.g. [2].
```

Two notes:
- **Say what to do, not just what not to do** — pair "don't use prior knowledge" with
  "base every claim on the supplied chunks."
- **Don't over-shout on newer models.** Capable models *overtrigger* on aggressive
  language — a calm "Answer only from the documents" now beats ALL-CAPS "CRITICAL: YOU
  MUST" (see [Module 2, lesson 02](../part-02-prompt-engineering/02-prompting-reasoning-models.md)).

⚠️ **The abstention paradox.** Counterintuitively, *adding context can make a model
**less** willing to say "I don't know"* — the extra material raises its confidence even
when the answer isn't actually there, producing confident wrong answers. Grounding +
explicit-abstention prompting is necessary but **not sufficient**; pair it with
retrieval-quality work and a **faithfulness eval**
([lesson 05](05-evaluation-security-and-production.md)).
[(Google Research — sufficient context)](https://research.google/blog/deeper-insights-into-retrieval-augmented-generation-the-role-of-sufficient-context/)

## 2. Allow "I don't know" — with a concrete string

Permit and *instruct* abstention, and make it testable:

```text
If the answer is not contained in the documents, respond exactly:
"I don't have enough information in the provided documents to answer that."
```

A fixed string is easy to detect and measure; a vague "say if you're unsure" isn't.

## 3. Citations

Two routes:

- **Native citations** (when your provider/API supports them — e.g. Anthropic's Citations
  feature): pass each chunk as a document block with citations enabled, and the response
  comes back with verifiable, **non-fabricated** pointers (char/page/block locations) into
  the exact source span. Anthropic reports up to **+15% citation recall** over
  prompt-based citing, and the cited text doesn't count as output tokens.
  ⚠️ **Incompatibility to know:** native Citations + **Structured Outputs** (strict JSON
  schema) returns a **400** — you can't have both in one call. If you need enforced JSON,
  use the prompt-based route below.
  [(Anthropic — Citations)](https://platform.claude.com/docs/en/build-with-claude/citations)
- **Prompt-based "quote first, then answer"**: have the model extract supporting verbatim
  quotes into `<quotes>` tags *before* answering, and base the answer only on them. Works
  anywhere (including alongside Structured Outputs); the quotes do count as output tokens.

## 4. Formatting & placing the chunks

Delimit retrieved chunks clearly and tag them with citable metadata. The XML-tag layout
(Claude-friendly, readable everywhere):

```xml
<documents>
  <document index="1">
    <source>docs/billing.md#refunds</source>
    <title>Refund Policy</title>
    <document_content>{{CHUNK_1}}</document_content>
  </document>
  <document index="2">
    <source>kb/onboarding.md</source>
    <document_content>{{CHUNK_2}}</document_content>
  </document>
</documents>

Using only the documents above, answer the question. Cite the source index per
claim, e.g. [1]. If the documents don't contain the answer, say so.

Question: {{QUESTION}}
```

**Placement rule (important):** put the **documents near the top, the question at the
end**. Anthropic reports queries-at-the-end can improve quality by up to ~30% on complex
multi-document inputs. (Same principle as long-context layout in
[Module 2, lesson 01](../part-02-prompt-engineering/01-core-techniques.md), and it also
helps **prompt caching** — stable docs first, volatile question last;
[lesson 05](05-evaluation-security-and-production.md).)

## 5. "Lost in the middle" — order matters

A foundational finding: models use information at the **beginning and end** of the context
far better than information in the **middle** — a **U-shaped** curve — *even for
long-context models*. A highly-relevant chunk buried mid-list can be effectively ignored.
[(Liu et al. 2023, "Lost in the Middle," TACL)](https://arxiv.org/abs/2307.03172)

**Mitigations:**
- **Rerank first** so the top chunk is genuinely the most relevant (lesson 03).
- **Reorder for the U-shape** — place the best chunks at the **start and end**, push weaker
  ones to the middle ("long-context reorder").
- **Don't over-stuff** — fewer, better chunks beat many noisy ones (next section).

## 6. How many chunks? Recall vs. noise

More chunks raise recall but lower precision, and **noise genuinely degrades answers** —
"context rot": across many models, reliability drops as input grows, even on simple tasks.
The resolution is the [lesson 03](03-retrieval-quality.md) pattern: **retrieve wide, rerank
to few.** Start around **top-20** (Anthropic's finding), then tune *down* against a
faithfulness/precision eval — the right number is corpus- and reranker-dependent, and
context rot is the counterweight against blindly inflating k.

## Putting it together (a Claude-flavored pipeline)

1. Contextualize chunks before indexing (lesson 03) →
2. Hybrid-retrieve wide, **rerank to ~top-20** →
3. **Reorder** best-first / U-shaped →
4. Assemble in `<documents>` **above** the question →
5. Instruct **answer-only** + a **concrete abstention** string →
6. Enable **native citations** (or quote-first if you need Structured Outputs) →
7. **Evaluate** faithfulness + context precision to tune k ([lesson 05](05-evaluation-security-and-production.md)).

---

## Next

→ [Evaluation, security & production](05-evaluation-security-and-production.md)
