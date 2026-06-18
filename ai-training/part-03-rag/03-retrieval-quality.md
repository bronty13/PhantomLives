---
title: Retrieval quality
module: 03 — Retrieval-Augmented Generation
lesson: 03
est_time: 40 min reading
last_reviewed: 2026-06-18
tags: [ai, rag, retrieval, reranking, hybrid-search, graphrag, agentic-rag]
---

# Retrieval quality

This is the most important lesson in the module. **Retrieval is the bottleneck** — the
generator can't answer from a fact it never received, and no prompt fixes a chunk that
wasn't retrieved. Most real-world RAG quality is won here.

The techniques stack roughly from "always do this" to "do this when a simple pipeline
isn't enough." Add them in response to evals ([lesson 05](05-evaluation-security-and-production.md)),
not all at once.

## Top-k: retrieve wide, then narrow

You fetch the *k* nearest chunks. The robust pattern is **two-stage**: a recall-oriented
first pass returns a **wide** candidate pool (top 50–150), then a precision step (rerank)
cuts it to the **few** that enter the prompt. Anthropic found **top-20 outperformed
top-10 and top-5** for their corpora — a reasonable starting default, then tune k against
your evals (more chunks = more recall but more noise; see "context rot" in
[lesson 04](04-generation-and-prompt-assembly.md)).

## Hybrid search (dense + sparse + fusion)

Dense (embedding) search captures meaning but misses exact tokens (codes, names, rare
terms); sparse (BM25/keyword) search nails exact tokens but misses paraphrases.
**Hybrid search runs both and fuses the rankings** — usually with **Reciprocal Rank
Fusion (RRF)**, which merges two ranked lists without needing comparable scores. Hybrid
+ rerank is one of the most reliable quality wins in production RAG. Make hybrid your
default unless you have a reason not to.

## Reranking (the highest-ROI add-on)

First-pass retrieval is fast but coarse — a **bi-encoder** embeds query and document
*separately*, so it can't model their interaction. A **reranker** is a **cross-encoder**:
it reads the query and a candidate chunk *together* and outputs a precise relevance score.
Far more accurate, but too slow to run over the whole corpus — so you run it only on the
top-N candidates from stage one.

- Pattern: **hybrid retrieve top ~150 → rerank → keep top ~20.**
- Options: **Cohere Rerank**, **Voyage Reranker**, open **BGE-reranker-v2 / Qwen3-Reranker**.
- Reranking drove Anthropic's retrieval-failure reduction from ~49% to **67%**.
- Bonus: it's often a *net latency and cost win* — over-retrieve cheaply, then hand the
  model a small, high-quality context instead of 20 noisy chunks ([lesson 05](05-evaluation-security-and-production.md)).

## Query transformation

The user's literal query is often a poor search key. Reshape it before retrieving
[(query transformation overview)](https://alexchernysh.com/blog/query-transformation-for-rag):

| Technique | What it does | Helps with |
|---|---|---|
| **Query rewriting** | Normalize: resolve pronouns, expand acronyms, de-chat | Messy/conversational queries |
| **HyDE** (Hypothetical Document Embeddings) | LLM writes a *hypothetical answer*; embed **that** and retrieve with it | Semantic alignment — a hypothetical answer sits closer to real passages than the question does |
| **Multi-query** | Generate several paraphrases, retrieve each, union results | Recall (covers multiple interpretations) |
| **Decomposition** | Split a complex multi-part question into sub-questions, retrieve per sub-question | *Structural* complexity (multi-part asks) |
| **Step-back** | Ask a broader, more abstract question first; retrieve on it + the original | *Informational* complexity (needs background) |

## Metadata filtering

Constrain retrieval with the structured metadata you attached at ingestion (date range,
source, department, **tenant, access level**) — applied *with* or *before* the vector
search. It improves accuracy by shrinking the candidate space, and it's **mandatory for
access control**: filter by the caller's verified permissions at retrieval time, never
after ([lesson 05](05-evaluation-security-and-production.md)).

## Advanced architectures

When hybrid + rerank isn't enough, reach for these:

### Contextual Retrieval (Anthropic)
Standalone chunks lose their context. Before indexing, prepend a short (50–100 token)
**LLM-generated blurb** situating each chunk in its document — applied to **both** the
embedding **and** the BM25 index. Results on top-20 retrieval failure (baseline 5.7%):
Contextual Embeddings alone **−35%**; + Contextual BM25 **−49%**; **+ reranking −67%**.
Affordable via prompt caching (~$1.02 per million document tokens). This single technique
beat upgrading from a cheap to an expensive embedder.
[(Anthropic — Contextual Retrieval)](https://www.anthropic.com/news/contextual-retrieval)

### Parent-document / small-to-big
Embed and retrieve on **small, precise** chunks, but feed the model the **larger parent**
passage they belong to — precision in matching, completeness in context.

### GraphRAG (Microsoft)
Extract entities and relationships into a **knowledge graph**, cluster it, and summarize
each cluster. **Local search** fans out from specific entities; **global search**
aggregates cluster summaries to answer holistic questions a vector index *can't* —
"what are the main themes across all documents?" Enables multi-hop reasoning.
⚠️ Original GraphRAG indexing is **expensive**; 2026 variants (**LightRAG**,
**LazyGraphRAG**, **Fast GraphRAG**) cut indexing cost by orders of magnitude.
[(Microsoft Research)](https://www.microsoft.com/en-us/research/blog/graphrag-improving-global-search-via-dynamic-community-selection/)

### Agentic RAG
Replace the fixed pipeline with an **agent** that treats retrieval as a *tool it decides
to call*: it can plan, choose among retrieval backends, reformulate the query, judge
whether the retrieved context is sufficient, and **loop** (re-retrieve) until it is. Best
for complex, multi-step questions where one retrieval pass isn't enough — at the cost of
more latency and tokens. (This is the bridge to the planned **Agents & Tool Use** module;
the agent loop itself is covered there.)

## The meta-point: adaptive routing

Don't run the heaviest pipeline on every query. Mature systems **route by complexity** —
a cheap single-shot hybrid retrieval for simple lookups, and contextual retrieval +
multi-query + GraphRAG/agentic loops only for queries that genuinely need them. Match
pipeline cost to query difficulty.

---

## Next

→ [Generation & prompt assembly](04-generation-and-prompt-assembly.md) — turning retrieved
chunks into a grounded, cited answer.
