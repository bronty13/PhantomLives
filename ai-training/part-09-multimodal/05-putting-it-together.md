---
title: Putting it together
module: 09 — Multimodal & Generative Media
lesson: 05
est_time: 30 min reading
last_reviewed: 2026-06-26
tags: [ai, multimodal, pipeline, capstone, cost, latency]
---

# Putting it together

The previous five lessons each took one cell of the
[modality matrix](00-multimodal-fundamentals.md) in isolation. Real products
chain several cells. This capstone wires them into a pipeline, then steps back
to the cost, latency, and evaluation picture of multimodal systems at scale —
folding Module 9 back into the operational disciplines of Modules 5–7.

---

## A worked pipeline: document → answer with citations

A common, genuinely useful multimodal system: a user uploads a folder of
**scanned** documents and asks questions; the system answers with citations back
to the source page. This chains four cells:

```
scanned PDF ──(1 vision/OCR)──▶ text + layout ──(2 embed)──▶ vector store
                                                                   │
user question ──(3 retrieve)──▶ relevant pages ──(4 generate)──▶ cited answer
```

1. **Ingest (image→text).** Because the pages are *scanned* (image-only, no text
   layer), you need [lesson 01](01-vision-and-documents.md)'s tier-2/3 reading:
   a layout-aware OCR pass (Mistral OCR, Textract) to get markdown + bounding
   boxes, **or** a vision LLM (Gemini, Claude native PDF) to extract directly.
   The [lesson 01 decision](01-vision-and-documents.md#the-three-ways-to-read-a-document)
   — dedicated OCR for cost-at-scale and table fidelity, LLM for flexibility —
   is the key call here.
2. **Embed & store.** Standard **[Module 3 — RAG](../part-03-rag/02-embeddings-and-vector-stores.md)**:
   chunk, embed, index. If charts/figures matter, use multimodal embeddings to
   keep the visuals retrievable.
3. **Retrieve.** Module 3's [retrieval-quality](../part-03-rag/03-retrieval-quality.md)
   toolkit (hybrid, rerank) is unchanged — this is the point of cross-linking
   rather than re-teaching.
4. **Generate with citations.** A vision-or-text LLM answers grounded in the
   retrieved pages. If you kept the page images, a model with native PDF +
   citations (Claude, [lesson 01](01-vision-and-documents.md#the-claude-lineup--modality--vision-pricing))
   can cite the exact page; bounding boxes from step 1 let you highlight the
   source region in your UI.

Notice the architecture: it's a **pipeline of specialists** (lesson 00), each
stage cheap, swappable, and individually debuggable. A native-multimodal model
could collapse steps 1+4, but you'd lose the ability to log the extracted text
and re-rank retrieval — the same tradeoff, made concrete.

---

## Cost & latency of multimodal at scale

Everything from **[Module 7](../part-07-cost-and-latency/00-fundamentals-and-the-triangle.md)**
applies, with multimodal-specific amplifications:

- **Resolution and clip-length are the master cost knobs** — the multimodal
  analogue of context length (lesson 00). Downscale images to the smallest size
  that resolves the needed detail; cap audio/video duration. This is the single
  biggest lever.
- **Right-size the model per stage** (Module 7's
  [routing lesson](../part-07-cost-and-latency/03-model-selection-and-routing.md)).
  Use a cheap, fast model for the high-volume OCR/transcription stage and a
  capable one only for the final reasoning. A FrugalGPT-style cascade works as
  well on images as on text.
- **Cache aggressively** (Module 7,
  [lesson 02](../part-07-cost-and-latency/02-caching.md)). Audio and image tokens
  cost *more* than text tokens, so prompt-caching a shared system prompt or a
  reused document pays off *harder* in multimodal than in text-only.
- **Batch the offline stages.** Bulk OCR and transcription are not
  latency-sensitive — run them through batch APIs (≈50% off) or a local model
  (lesson 04, ≈free at volume).
- **Latency stacks in a cascade** (lesson 02). For interactive multimodal,
  the TTFT discipline of Module 7's
  [latency lesson](../part-07-cost-and-latency/04-latency-engineering.md) is what
  keeps it responsive; for a live voice agent, that's the case for going native.

---

## Evaluating multimodal systems

The **[Module 5 — Evaluation](../part-05-evaluation/00-the-eval-mindset.md)**
discipline is unchanged — evals are still the moat — but multimodal needs grading
methods text evals don't:

- **OCR / extraction** grades against a ground-truth transcript or field set:
  character/word error rate, field-level precision/recall. This is the
  *reliable, code-based* end of Module 5's
  [grading hierarchy](../part-05-evaluation/02-grading-methods.md) — prefer it.
- **Generated media** (images, audio, video) is the *hard* end — there's rarely
  one right answer. You fall back to
  [LLM-as-judge](../part-05-evaluation/03-llm-as-judge.md) (a vision model scoring
  "does this image match the brief?"), reference-based metrics (CLIP similarity),
  or human raters. Treat automated media scores as noisy, exactly as Module 5
  warns about judges.
- **Voice agents** need eval at *both* layers — the ASR transcript (WER) and the
  end-to-end conversation (task success, interruption handling) — because a clean
  transcript can still feed a bad reply.

---

## Where multimodal sits in the whole course

Module 9 is the point where the course's left-to-right "text in, text out"
assumption finally drops, and every prior module turns out to extend cleanly:

- **Choosing a model** ([M1](../part-01-model-landscape/00-how-to-choose-a-model.md))
  now includes a modality axis — and the realization that no one model fills the
  grid.
- **Prompting** ([M2](../part-02-prompt-engineering/00-prompting-fundamentals.md))
  extends to image and generation prompts.
- **RAG** ([M3](../part-03-rag/00-rag-fundamentals.md)) gains multimodal
  embeddings and document ingestion.
- **Agents** ([M4](../part-04-agents-and-tool-use/00-agent-fundamentals.md)) gain
  vision (computer-use grounding) and voice as input/output surfaces.
- **Eval, cost, local** ([M5](../part-05-evaluation/00-the-eval-mindset.md)–[M8](../part-08-local-inference/00-why-and-the-local-stack.md))
  all apply with multimodal-specific wrinkles called out above.

`★ Insight ─────────────────────────────────────`
- **A multimodal product is a pipeline of single-cell stages**, and that's a
  feature, not a limitation — each stage inherits a whole module's worth of
  discipline (RAG retrieval, model routing, caching, eval) you already know.
- **The amplification pattern is consistent:** image/audio/video tokens cost
  more and stack more latency than text, so Module 7's levers — resolution
  control, right-sizing, caching, batching — matter *more* here, not less.
`─────────────────────────────────────────────────`

## Next

This completes Module 9. → Back to the
[curriculum index](../CURRICULUM.md), or on to **Module 10 — Coding Agents &
AI-Assisted Development** (the next build), which takes the agent foundations of
Module 4 into the daily reality of AI-assisted software work.
