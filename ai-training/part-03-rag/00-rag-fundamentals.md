---
title: RAG fundamentals
module: 03 — Retrieval-Augmented Generation
lesson: 00
est_time: 30 min reading
last_reviewed: 2026-06-18
tags: [ai, rag, retrieval, fundamentals]
---

# RAG fundamentals

**Retrieval-Augmented Generation (RAG)** gives a model facts it doesn't have in its
weights by *fetching relevant documents at query time* and putting them in the prompt.
It's how you make a model answer from your private docs, from data newer than its
training cutoff, and *with citations* — without retraining anything.

This module follows [Module 2 — Prompt Engineering](../part-02-prompt-engineering/00-prompting-fundamentals.md);
RAG is, at its core, "automatically build a well-grounded prompt." Several pieces
(grounding instructions, citations, structured output, prompt injection) are covered
there — this module points back rather than repeating them.

## The pipeline

RAG has two phases. The first runs **offline** (when documents change); the second runs
**per request**.

**Indexing (offline):**
1. **Ingest** — pull in source documents (PDFs, web pages, DB rows, wiki, tickets).
2. **Parse** — extract clean text + structure (headings, tables).
3. **Chunk** — split into retrieval-sized units ([lesson 01](01-ingestion-and-chunking.md)).
4. **Embed** — encode each chunk into a vector (often also a keyword index) ([lesson 02](02-embeddings-and-vector-stores.md)).
5. **Store/index** — write vectors + metadata to a vector database.

**Querying (per request):**
6. **Retrieve** — embed the query, find the nearest chunks (and/or keyword-match).
7. **Rerank** *(optional but high-value)* — re-score candidates for precision ([lesson 03](03-retrieval-quality.md)).
8. **Augment** — assemble the chosen chunks into the prompt with the question ([lesson 04](04-generation-and-prompt-assembly.md)).
9. **Generate** — the model answers, grounded in (and citing) the retrieved text.

```
  Docs → Parse → Chunk → Embed → [Vector DB]        (offline, on change)
                                      ▲
  Query → Embed → Retrieve → Rerank ──┘→ Augment prompt → LLM → grounded answer
```

Steps 6–9 are the baseline; [lesson 03](03-retrieval-quality.md) shows where 2026
systems break the straight line (agentic loops, graph traversal).

## Why RAG

- **Grounding / fewer hallucinations** — answers anchor to retrieved source text.
- **Fresh & private knowledge** — use data created after the training cutoff, and
  internal data the model never saw, with no retraining.
- **Citations & provenance** — show *which* document a claim came from (audit/compliance).
- **Cost & access control** — feed only the relevant slice into context (not the whole
  corpus every call), and enforce per-user/row-level permissions *at retrieval time* —
  something baked-in weights fundamentally can't do.

## The decision: RAG vs. long-context vs. fine-tuning

This is the durable part — learn it; the model specifics below will drift.

A persistent myth is *"1M–2M-token context windows killed RAG."* They didn't. The 2026
consensus is these are **complementary, not competing**:

| Approach | Wins when | Watch out for |
|---|---|---|
| **RAG** | Large or changing knowledge base; you need citations/provenance; per-user access control; no labeled training data | Retrieval quality is the ceiling (lesson 03) |
| **Long-context** (stuff it all in the prompt) | Small, fairly *static* corpus | Anthropic's rule of thumb: **under ~200K tokens (~500 pages), skip RAG** — put it all in the prompt with prompt caching. But you re-pay for the whole corpus *every* call, and it doesn't scale past a few hundred pages. Also "lost in the middle" / context rot ([lesson 04](04-generation-and-prompt-assembly.md)). |
| **Fine-tuning** | Consistent output *format/style*, classification, latency-critical paths; large, stable, labeled dataset | Teaches *behavior, not facts*; no citations; bad for changing knowledge |

**Why long context doesn't kill RAG:** scale (corpora dwarf even 2M tokens), cost
(re-paying for the corpus per query), freshness (RAG re-indexes without re-prompting),
citations (RAG returns the exact source span), and access control (retrieval filters by
permission). The mature pattern is **hybrid**: volatile knowledge → RAG; stable behavior
→ fine-tune; small static context → long-context prompt.
[(Anthropic — Contextual Retrieval)](https://www.anthropic.com/news/contextual-retrieval)

## When RAG is the *wrong* tool

| If you need… | Prefer over plain RAG |
|---|---|
| A corpus that fits the window (<~200K tokens) | Long-context + prompt caching |
| Consistent style/format, stable facts, low latency at volume | Fine-tuning |
| Complex, open-ended, multi-hop questions on fresh data | **Agentic / iterative search** (retrieval as a tool the model loops on — lesson 03) |
| Counts, sums, exact filters, tabular answers | **Text-to-SQL / direct DB query** — vector search returns *similar*, not *exact*; it can't `COUNT`/`GROUP BY` |
| "What are the themes across the *whole* corpus?" | **GraphRAG** — plain RAG retrieves local chunks, not global structure (lesson 03) |

## The 2026 framing: RAG is a spectrum

RAG isn't one technique; it's a spectrum from "embed + top-k + stuff" to contextual
retrieval + hybrid + rerank + agentic loops + graphs. The best production systems use
**adaptive routing** — match *query complexity* to *pipeline complexity*: cheap
single-shot retrieval for simple lookups, the heavy machinery only when a query needs it.
Start simple; add a stage only when an eval ([lesson 05](05-evaluation-security-and-production.md))
shows you need it.

---

## Next

→ [Ingestion & chunking](01-ingestion-and-chunking.md)
