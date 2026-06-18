---
title: Ingestion & chunking
module: 03 — Retrieval-Augmented Generation
lesson: 01
est_time: 30 min reading
last_reviewed: 2026-06-18
tags: [ai, rag, ingestion, chunking, parsing]
---

# Ingestion & chunking

Garbage in, garbage retrieved. The unglamorous front of the pipeline — parsing and
chunking — sets a hard ceiling on everything downstream. A great embedding model can't
rescue a chunk that was split mid-table or mid-sentence.

## Parsing & cleaning come first

The chunker is only as good as the text the parser hands it.

- **PDFs** are the hard case: layout-aware extraction, multi-column flow, and **tables**
  break naive text extraction. Page-aware parsing preserves tables and layout.
- **HTML:** strip boilerplate (nav, ads, footers) but **keep semantic structure** —
  headings, lists, tables.
- **Clean** whitespace/encoding and drop junk, but **preserve heading hierarchy and table
  structure** — both feed structure-aware chunking and the metadata you'll attach.

If retrieval is mysteriously bad, inspect the *parsed text* before blaming the embedder —
mangled tables and merged columns are a common silent culprit.

## Chunking strategies

Splitting documents into retrieval units. The options, and when each fits:

| Strategy | What it is | Use when |
|---|---|---|
| **Fixed-size** | Split every N tokens/chars, optional sliding overlap | Prototyping, uniform content. Fast, but fragments sentences. |
| **Recursive / character** | Split at natural boundaries in order (paragraph → line → sentence → word) | **The default for ~80% of cases** — best end-to-end accuracy in benchmarks, fast, cheap. |
| **Sentence-based** | Group whole sentences to a target size | Q&A, transcripts, conversational data. |
| **Semantic** | Embed sentences, split where topic/embedding similarity drops | Dense unstructured prose, when accuracy justifies the cost (it's slower). Modest recall gains; recent analysis questions the cost/benefit. |
| **Structure-aware** | Split along the doc's own structure (Markdown headings, sections) | Documentation, technical content — and lets you attach heading-path metadata. |
| **LLM-based** | Ask a model to pick logical split points | High-value/complex content; usually too slow/costly at scale. |
| **Late chunking** *(newer)* | Embed the **whole document first**, then split the *token embeddings* — each chunk's vector carries full-doc context | Docs with cross-chunk references (contracts, papers); needs a long-context embedding model. |
| **Contextual chunking** *(newer)* | Prepend an LLM-generated context blurb to each chunk *before* embedding | When chunks are ambiguous alone — the highest-impact variant (see below + [lesson 03](03-retrieval-quality.md)). |

[(Firecrawl — chunking strategies)](https://www.firecrawl.dev/blog/best-chunking-strategies-rag)

**Default recommendation:** start with **recursive splitting at ~400–512 tokens**. It's
the strongest general baseline; only move to semantic/late/contextual if an eval shows
retrieval is missing things.

## Chunk size & overlap

- **Size:** ~512 tokens is the usual default (range 256–1024). Short factoid Q&A →
  256–512; long-form legal/technical/analytical → 1024+.
- **Overlap is now *contested*.** The traditional rule is 10–20% overlap (≈50–100 tokens
  on a 500-token chunk) so a sentence split across a boundary still appears whole. But a
  2026 systematic study found overlap gave **no measurable benefit** and only raised
  indexing cost. ⚠️ Treat overlap as *"test it on your data,"* not dogma.
- **The right size is empirical.** It depends on your docs, your embedder's context limit,
  and your queries — tune it against a retrieval eval ([lesson 05](05-evaluation-security-and-production.md)),
  don't guess.

## Metadata is not optional

Attach structured metadata to every chunk at ingestion:

- **source** (filename/URL), **title**, **heading path**, **page/section**
- **dates** (created/updated — for freshness filtering)
- **author / department**
- **permissions / tenant / access level** — load-bearing for security ([lesson 05](05-evaluation-security-and-production.md))

Metadata powers three things you'll need later: **filtering** (constrain retrieval by
date/source/tenant — [lesson 03](03-retrieval-quality.md)), **citations** (point back to
the source — [lesson 04](04-generation-and-prompt-assembly.md)), and **access control**
(filter by the caller's permissions *at retrieval time*). Capture it now; you can't
reconstruct it later.

## The standout technique: contextual chunking

A chunk like *"Revenue grew 3% this quarter"* is useless in isolation — *which company?
which quarter?* **Contextual chunking** (Anthropic's "Contextual Retrieval") prepends a
short, LLM-generated blurb situating each chunk in its document *before* embedding and
keyword-indexing it. Anthropic reports it cuts retrieval failures by ~35–49% (up to 67%
with reranking), affordably via prompt caching. The full mechanism — and why it's both a
chunking move and a retrieval move — is in [lesson 03](03-retrieval-quality.md).

---

## Next

→ [Embeddings & vector stores](02-embeddings-and-vector-stores.md)
